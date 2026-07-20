"""
Rehab exercise video storage — Google Drive backed.

Uploaded workout videos are stored exactly like Medical Records and Study
Materials: the file lives in Google Drive, only metadata lives in MSSQL, and
patients stream it through FastAPI (never a direct Drive URL, never a local
filesystem path).

Folder layout:
    RehabilitationVideos/
        Program_<program-uuid>/
            <original file name>
"""
import logging
import re

from app.services.google_drive_service import GoogleDriveService

logger = logging.getLogger(__name__)

REHAB_VIDEOS_ROOT = "RehabilitationVideos"


def _sanitize_name(name: str) -> str:
    """Drive is permissive, but strip path separators and control chars so a
    crafted filename can't look like a path or break the folder listing."""
    cleaned = re.sub(r'[\\/\x00-\x1f]', "_", name).strip()
    return cleaned or "video.mp4"


class RehabVideoService:
    def __init__(self) -> None:
        self._drive = GoogleDriveService()

    def store(self, program_id, file_name: str, mime_type: str, fileobj) -> tuple[str, str]:
        """Resumable-upload a video into RehabilitationVideos/Program_<id>/.
        Returns (drive_file_id, folder_id). Bounded memory — safe for large files."""
        return self._drive.upload_stream_to_subfolder(
            REHAB_VIDEOS_ROOT,
            f"Program_{program_id}",
            _sanitize_name(file_name),
            mime_type,
            fileobj,
        )

    def file_size(self, file_id: str) -> int:
        return self._drive.get_file_size(file_id)

    def read_range(self, file_id: str, start: int, end: int) -> bytes:
        return self._drive.download_range(file_id, start, end)

    def stream(self, file_id: str, chunk_size: int = 2 * 1024 * 1024):
        return self._drive.stream_file(file_id, chunk_size=chunk_size)

    def remove(self, file_id: str) -> None:
        self._drive.delete_file(file_id)
