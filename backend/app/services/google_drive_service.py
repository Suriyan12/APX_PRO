"""
Google Drive client for the Medical Records module.

All Drive access in the application goes through this class. Files live in the
configured OAuth account's own Drive and are never shared or made public — the
only way to reach them is through the authenticated FastAPI endpoints.
"""
import io
import logging
import threading
from typing import Dict, Optional

from app.core.config import settings

logger = logging.getLogger(__name__)

FOLDER_MIME_TYPE = "application/vnd.google-apps.folder"


class GoogleDriveError(Exception):
    """Raised when a Google Drive operation fails."""

    def __init__(self, message: str, status_code: int = 502):
        super().__init__(message)
        self.message = message
        self.status_code = status_code


class GoogleDriveNotConfiguredError(GoogleDriveError):
    def __init__(self):
        super().__init__(
            "Document storage is not configured. Set GDRIVE_OAUTH_CLIENT_ID, "
            "GDRIVE_OAUTH_CLIENT_SECRET and GDRIVE_OAUTH_REFRESH_TOKEN in .env "
            "(run get_gdrive_token.py to generate them).",
            status_code=503,
        )


class GoogleDriveService:
    """Thin wrapper over the Drive v3 API. The client is built lazily so the
    application can boot (and every non-Drive feature keeps working) even when
    the service account is not configured yet."""

    # Credentials are shared process-wide so the OAuth access token is fetched
    # once and reused. The API *service* (and its underlying httplib2
    # transport) is PER-INSTANCE: httplib2 is not thread-safe, and a shared
    # service caused interleaved writes on one TLS socket under concurrent
    # requests (video players issue parallel Range requests), surfacing as
    # "SSL: WRONG_VERSION_NUMBER". Each request handler constructs its own
    # GoogleDriveService, so transports are never shared across threads.
    _credentials = None
    _credentials_lock = threading.Lock()
    # Cache of resolved folder ids (key: "name|parent_id") shared across
    # instances. Prevents duplicate folder creation and repeated Drive lookups
    # for the same folder within a process. Guarded by a lock so two concurrent
    # first-uploads cannot each create the folder.
    _folder_cache: Dict[str, str] = {}
    _folder_lock = threading.Lock()

    def __init__(self) -> None:
        self._service_instance = None

    @classmethod
    def _get_credentials(cls):
        if cls._credentials is None:
            with cls._credentials_lock:
                if cls._credentials is None:
                    cls._credentials = cls._build_credentials()
        return cls._credentials

    def _get_service(self):
        if self._service_instance is not None:
            return self._service_instance

        try:
            # Imported lazily so a missing dependency does not break startup.
            from googleapiclient.discovery import build
        except ImportError:
            raise GoogleDriveError(
                "Google API client is not installed. Run: pip install google-api-python-client google-auth",
                status_code=503,
            )

        self._service_instance = build(
            "drive", "v3", credentials=self._get_credentials(), cache_discovery=False
        )
        return self._service_instance

    @staticmethod
    def _build_credentials():
        """OAuth 2.0 user credentials — files are owned by (and stored in)
        the configured Google account's own Drive. Service accounts are not
        supported: Google gives them no storage quota, so their uploads fail
        with HTTP 403 outside a Workspace Shared Drive.

        The refresh token is generated once via get_gdrive_token.py and lives
        only in server-side .env; the access token is refreshed automatically.
        """
        if not (
            settings.GDRIVE_OAUTH_CLIENT_ID
            and settings.GDRIVE_OAUTH_CLIENT_SECRET
            and settings.GDRIVE_OAUTH_REFRESH_TOKEN
        ):
            raise GoogleDriveNotConfiguredError()

        from google.oauth2.credentials import Credentials

        return Credentials(
            token=None,
            refresh_token=settings.GDRIVE_OAUTH_REFRESH_TOKEN,
            client_id=settings.GDRIVE_OAUTH_CLIENT_ID,
            client_secret=settings.GDRIVE_OAUTH_CLIENT_SECRET,
            token_uri="https://oauth2.googleapis.com/token",
            scopes=["https://www.googleapis.com/auth/drive"],
        )

    # ── Folder management ─────────────────────────────────────────────────────

    def _find_folder(self, name: str, parent_id: Optional[str]) -> Optional[str]:
        service = self._get_service()
        escaped = name.replace("'", "\\'")
        query = (
            f"name = '{escaped}' and mimeType = '{FOLDER_MIME_TYPE}' and trashed = false"
        )
        if parent_id:
            query += f" and '{parent_id}' in parents"
        try:
            result = service.files().list(
                q=query,
                spaces="drive",
                fields="files(id)",
                pageSize=1,
                supportsAllDrives=True,
                includeItemsFromAllDrives=True,
            ).execute()
        except Exception as e:
            raise self._wrap(e, "Failed to look up Drive folder")
        files = result.get("files", [])
        return files[0]["id"] if files else None

    def _create_folder(self, name: str, parent_id: Optional[str]) -> str:
        service = self._get_service()
        metadata = {"name": name, "mimeType": FOLDER_MIME_TYPE}
        if parent_id:
            metadata["parents"] = [parent_id]
        try:
            folder = service.files().create(
                body=metadata, fields="id", supportsAllDrives=True
            ).execute()
        except Exception as e:
            raise self._wrap(e, "Failed to create Drive folder")
        return folder["id"]

    def _validate_folder(self, folder_id: str) -> bool:
        """True if folder_id points to a live (non-trashed) folder in the
        current account's Drive. Used to detect stale ids after an account or
        credential change."""
        service = self._get_service()
        try:
            meta = service.files().get(
                fileId=folder_id,
                fields="id, trashed, mimeType",
                supportsAllDrives=True,
            ).execute()
        except Exception as e:
            if self._http_status(e) == 404:
                return False
            raise self._wrap(e, "Failed to validate Drive folder")
        return not meta.get("trashed", False) and meta.get("mimeType") == FOLDER_MIME_TYPE

    def _ensure_folder(self, name: str, parent_id: Optional[str]) -> str:
        """Find-or-create a folder, idempotently. The lock + cache guarantee a
        folder with a given (name, parent) is only ever created once per
        process, so duplicate folders are never produced under concurrency."""
        cache_key = f"{name}|{parent_id or ''}"
        cached = GoogleDriveService._folder_cache.get(cache_key)
        if cached:
            return cached
        with GoogleDriveService._folder_lock:
            # Re-check inside the lock in case another thread just created it.
            cached = GoogleDriveService._folder_cache.get(cache_key)
            if cached:
                return cached
            folder_id = self._find_folder(name, parent_id) or self._create_folder(
                name, parent_id
            )
            GoogleDriveService._folder_cache[cache_key] = folder_id
            return folder_id

    def ensure_root_folder(self) -> str:
        """Return the id of the MedicalRecords root folder, discovering or
        creating it automatically. An optional GDRIVE_ROOT_FOLDER_ID is treated
        as a hint only: if it no longer resolves (e.g. after an account change)
        it is ignored and the folder is rediscovered by name."""
        cache_key = "__root__"
        cached = GoogleDriveService._folder_cache.get(cache_key)
        if cached:
            return cached
        with GoogleDriveService._folder_lock:
            cached = GoogleDriveService._folder_cache.get(cache_key)
            if cached:
                return cached
            pinned = (settings.GDRIVE_ROOT_FOLDER_ID or "").strip()
            if pinned and self._validate_folder(pinned):
                root_id = pinned
            else:
                if pinned:
                    logger.warning(
                        "GDRIVE_ROOT_FOLDER_ID %s is invalid for the current "
                        "account; rediscovering '%s' by name.",
                        pinned, settings.GDRIVE_ROOT_FOLDER_NAME,
                    )
                root_id = self._find_folder(
                    settings.GDRIVE_ROOT_FOLDER_NAME, parent_id=None
                ) or self._create_folder(
                    settings.GDRIVE_ROOT_FOLDER_NAME, parent_id=None
                )
            GoogleDriveService._folder_cache[cache_key] = root_id
            return root_id

    def ensure_patient_folder(self, patient_key: str) -> str:
        """Return the id of MedicalRecords/Patient_<key>/, creating it if needed."""
        root_id = self.ensure_root_folder()
        return self._ensure_folder(f"Patient_{patient_key}", parent_id=root_id)

    def ensure_root_by_name(self, name: str) -> str:
        """Discover-or-create a top-level folder by name (e.g. 'StudyMaterials').
        Generic sibling of ensure_root_folder for modules other than Medical
        Records; reuses the same cache + lock so no duplicate folders appear."""
        return self._ensure_folder(name, parent_id=None)

    def ensure_subfolder(self, root_name: str, sub_name: str) -> str:
        """Discover-or-create <root_name>/<sub_name>/ (e.g.
        StudyMaterials/Psychology), creating either level if missing."""
        root_id = self.ensure_root_by_name(root_name)
        return self._ensure_folder(sub_name, parent_id=root_id)

    @classmethod
    def invalidate_folder_cache(cls) -> None:
        """Drop all cached folder ids (root + patient). Called when a stale id
        is detected so the next resolution rediscovers folders from Drive."""
        with cls._folder_lock:
            cls._folder_cache.clear()

    # ── File operations ───────────────────────────────────────────────────────

    def upload_file(self, folder_id: str, file_name: str, mime_type: str, data: bytes) -> str:
        service = self._get_service()
        from googleapiclient.http import MediaIoBaseUpload

        media = MediaIoBaseUpload(io.BytesIO(data), mimetype=mime_type, resumable=False)
        metadata = {"name": file_name, "parents": [folder_id]}
        try:
            created = service.files().create(
                body=metadata, media_body=media, fields="id", supportsAllDrives=True
            ).execute()
        except Exception as e:
            raise self._wrap(e, "Failed to upload file to Drive")
        return created["id"]

    def _upload_with_recovery(
        self,
        resolve_folder,
        file_name: str,
        mime_type: str,
        data: bytes,
        preferred_folder_id: Optional[str] = None,
    ) -> tuple[str, str]:
        """Upload into a folder, self-healing stale ids. Tries
        `preferred_folder_id` first (typically the id stored in MSSQL); on a 404
        (e.g. after an account/credential change) it clears the folder cache,
        re-resolves the folder via `resolve_folder()` and retries once.
        Returns (drive_file_id, folder_id_actually_used) — callers should
        persist the folder id so the database self-heals."""
        folder_id = preferred_folder_id or resolve_folder()
        try:
            return self.upload_file(folder_id, file_name, mime_type, data), folder_id
        except GoogleDriveError as e:
            if e.status_code != 404:
                raise
            logger.warning(
                "Drive folder %s not found (stale/deleted); rediscovering and "
                "retrying upload.", folder_id,
            )
            self.invalidate_folder_cache()
            folder_id = resolve_folder()
            return self.upload_file(folder_id, file_name, mime_type, data), folder_id

    def upload_to_patient(
        self,
        patient_key: str,
        file_name: str,
        mime_type: str,
        data: bytes,
        preferred_folder_id: Optional[str] = None,
    ) -> tuple[str, str]:
        """Upload into MedicalRecords/Patient_<key>/, self-healing on stale ids.
        Returns (drive_file_id, folder_id_actually_used)."""
        return self._upload_with_recovery(
            lambda: self.ensure_patient_folder(patient_key),
            file_name, mime_type, data, preferred_folder_id,
        )

    def upload_to_category(
        self,
        root_name: str,
        category: str,
        file_name: str,
        mime_type: str,
        data: bytes,
        preferred_folder_id: Optional[str] = None,
    ) -> tuple[str, str]:
        """Upload into <root_name>/<category>/, self-healing on stale ids.
        Returns (drive_file_id, folder_id_actually_used)."""
        return self._upload_with_recovery(
            lambda: self.ensure_subfolder(root_name, category),
            file_name, mime_type, data, preferred_folder_id,
        )

    def upload_stream(self, folder_id: str, file_name: str, mime_type: str, fileobj) -> str:
        """Resumable chunked upload from a file-like object — bounded memory,
        suitable for large videos. Returns the new Drive file id."""
        service = self._get_service()
        from googleapiclient.http import MediaIoBaseUpload

        fileobj.seek(0)
        media = MediaIoBaseUpload(
            fileobj, mimetype=mime_type, resumable=True, chunksize=8 * 1024 * 1024
        )
        metadata = {"name": file_name, "parents": [folder_id]}
        try:
            request = service.files().create(
                body=metadata, media_body=media, fields="id", supportsAllDrives=True
            )
            response = None
            while response is None:
                _, response = request.next_chunk()
        except Exception as e:
            raise self._wrap(e, "Failed to upload file to Drive")
        return response["id"]

    def upload_stream_to_subfolder(
        self,
        root_name: str,
        sub_name: str,
        file_name: str,
        mime_type: str,
        fileobj,
    ) -> tuple[str, str]:
        """Resumable upload into <root_name>/<sub_name>/, self-healing on stale
        folder ids (same recovery semantics as _upload_with_recovery).
        Returns (drive_file_id, folder_id_actually_used)."""
        folder_id = self.ensure_subfolder(root_name, sub_name)
        try:
            return self.upload_stream(folder_id, file_name, mime_type, fileobj), folder_id
        except GoogleDriveError as e:
            if e.status_code != 404:
                raise
            logger.warning(
                "Drive folder %s not found (stale/deleted); rediscovering and "
                "retrying streamed upload.", folder_id,
            )
            self.invalidate_folder_cache()
            folder_id = self.ensure_subfolder(root_name, sub_name)
            return self.upload_stream(folder_id, file_name, mime_type, fileobj), folder_id

    def upload_stream_to_patient(
        self,
        patient_key: str,
        file_name: str,
        mime_type: str,
        fileobj,
        preferred_folder_id: Optional[str] = None,
    ) -> tuple[str, str]:
        """Resumable, bounded-memory upload into MedicalRecords/Patient_<key>/,
        self-healing on stale folder ids (same recovery semantics as
        _upload_with_recovery, but streamed). Returns
        (drive_file_id, folder_id_actually_used)."""
        folder_id = preferred_folder_id or self.ensure_patient_folder(patient_key)
        try:
            return self.upload_stream(folder_id, file_name, mime_type, fileobj), folder_id
        except GoogleDriveError as e:
            if e.status_code != 404:
                raise
            logger.warning(
                "Drive folder %s not found (stale/deleted); rediscovering and "
                "retrying streamed patient upload.", folder_id,
            )
            self.invalidate_folder_cache()
            folder_id = self.ensure_patient_folder(patient_key)
            return self.upload_stream(folder_id, file_name, mime_type, fileobj), folder_id

    def download_file(self, file_id: str) -> bytes:
        service = self._get_service()
        from googleapiclient.http import MediaIoBaseDownload

        buffer = io.BytesIO()
        try:
            request = service.files().get_media(fileId=file_id)
            downloader = MediaIoBaseDownload(buffer, request)
            done = False
            while not done:
                _, done = downloader.next_chunk()
        except Exception as e:
            raise self._wrap(e, "Failed to download file from Drive")
        return buffer.getvalue()

    def get_file_size(self, file_id: str) -> int:
        """Return the file's size in bytes (for HTTP Range responses)."""
        service = self._get_service()
        try:
            meta = service.files().get(
                fileId=file_id, fields="size", supportsAllDrives=True
            ).execute()
        except Exception as e:
            raise self._wrap(e, "Failed to read file size from Drive")
        return int(meta.get("size") or 0)

    def download_range(self, file_id: str, start: int, end: int) -> bytes:
        """Download bytes [start, end] inclusive via a Drive Range request, so
        only the requested portion is fetched (enables progressive PDF loading
        without downloading the whole file)."""
        service = self._get_service()
        try:
            request = service.files().get_media(fileId=file_id)
            request.headers["Range"] = f"bytes={start}-{end}"
            return request.execute()
        except Exception as e:
            raise self._wrap(e, "Failed to download file range from Drive")

    def stream_file(self, file_id: str, chunk_size: int = 2 * 1024 * 1024):
        """Yield the file in chunks straight from Drive (bounded memory) for
        StreamingResponse — avoids buffering the whole file on the server."""
        service = self._get_service()
        from googleapiclient.http import MediaIoBaseDownload

        buffer = io.BytesIO()
        try:
            request = service.files().get_media(fileId=file_id)
            downloader = MediaIoBaseDownload(buffer, request, chunksize=chunk_size)
            done = False
            while not done:
                _, done = downloader.next_chunk()
                data = buffer.getvalue()
                if data:
                    yield data
                    buffer.seek(0)
                    buffer.truncate(0)
        except Exception as e:
            raise self._wrap(e, "Failed to stream file from Drive")

    def delete_file(self, file_id: str) -> None:
        """Delete a Drive file. A file that is already gone is not an error."""
        service = self._get_service()
        try:
            service.files().delete(fileId=file_id, supportsAllDrives=True).execute()
        except Exception as e:
            if self._http_status(e) == 404:
                logger.warning("Drive file %s already deleted", file_id)
                return
            raise self._wrap(e, "Failed to delete file from Drive")

    # ── Error helpers ─────────────────────────────────────────────────────────

    @staticmethod
    def _http_status(exc: Exception) -> Optional[int]:
        resp = getattr(exc, "resp", None)
        return getattr(resp, "status", None)

    def _wrap(self, exc: Exception, message: str) -> GoogleDriveError:
        if isinstance(exc, GoogleDriveError):
            return exc
        # Preserve the underlying HTTP status (e.g. 404) so callers can react
        # to stale folder ids; fall back to 502 for opaque failures.
        status = self._http_status(exc) or 502
        logger.error("%s: %s", message, exc)
        return GoogleDriveError(message, status_code=status)
