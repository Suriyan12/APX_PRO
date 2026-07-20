"""
StudyMaterialService — Google Drive storage for the Study Materials (Notes)
module.

Reuses GoogleDriveService so there is no duplicate Drive logic. Files are
organised as StudyMaterials/<Category>/ and only their metadata is stored in
MSSQL (on the Note model). This service is storage-focused; note metadata,
access control and premium gating stay in the notes router.
"""
import re
from typing import Optional, Tuple

from app.services.google_drive_service import GoogleDriveService

STUDY_MATERIALS_ROOT = "StudyMaterials"


def _sanitize_folder_name(name: str) -> str:
    """Category names become Drive folder names, so strip anything unsafe."""
    cleaned = re.sub(r"[^A-Za-z0-9._ &\-()]", "_", (name or "").strip())
    return cleaned[:100] or "Uncategorized"


class StudyMaterialService:
    def __init__(self):
        self.drive = GoogleDriveService()

    def store(
        self,
        category: str,
        file_name: str,
        mime_type: str,
        data: bytes,
        preferred_folder_id: Optional[str] = None,
    ) -> Tuple[str, str]:
        """Upload a file into StudyMaterials/<Category>/, creating the root and
        category folders if needed. Returns (drive_file_id, folder_id_used).
        Self-heals if a previously stored folder id has gone stale."""
        return self.drive.upload_to_category(
            root_name=STUDY_MATERIALS_ROOT,
            category=_sanitize_folder_name(category),
            file_name=file_name,
            mime_type=mime_type,
            data=data,
            preferred_folder_id=preferred_folder_id,
        )

    def read(self, file_id: str) -> bytes:
        """Download raw bytes for streaming through FastAPI."""
        return self.drive.download_file(file_id)

    def remove(self, file_id: str) -> None:
        """Delete the underlying Drive file (404 is treated as already gone)."""
        self.drive.delete_file(file_id)
