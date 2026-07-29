"""
M7(a): a discount code's used_count must be restored if the booking insert
fails after the count was incremented — otherwise the code is silently burned.
"""
import pytest

from app.models.models import DiscountCode, DiscountType, User
from app.repositories.appointment_repository import AppointmentRepository
from app.schemas.schemas import AppointmentCreate
from app.services.appointment_service import AppointmentService
from tests.conftest import PATIENT_A_ID, future_slot


def test_discount_restored_when_booking_fails(db, monkeypatch):
    code = DiscountCode(
        code="SAVE10",
        discount_type=DiscountType.PERCENTAGE,
        discount_value=10,
        max_uses=5,
        used_count=0,
        is_active=True,
    )
    db.add(code)
    db.commit()
    db.refresh(code)
    try:
        repo = AppointmentRepository(db)
        svc = AppointmentService(repo)

        def _boom(*a, **k):
            raise RuntimeError("simulated insert failure")

        monkeypatch.setattr(repo, "create", _boom)

        user = db.get(User, PATIENT_A_ID)
        start, end = future_slot(days=11)
        payload = AppointmentCreate(start_time=start, end_time=end, discount_code="SAVE10")

        with pytest.raises(RuntimeError):
            svc.book(payload, user)

        db.refresh(code)
        assert code.used_count == 0, "discount count should be restored on failure"
    finally:
        db.delete(code)
        db.commit()
