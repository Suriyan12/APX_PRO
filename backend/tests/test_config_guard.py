"""
M5: DEVELOPMENT_MODE must never be enabled in production (it bypasses payment
for Notes). The Settings model should refuse to construct that combination.
"""
import pytest
from pydantic import ValidationError

from app.core.config import Settings


def test_dev_mode_in_production_is_rejected():
    with pytest.raises(ValidationError):
        Settings(
            _env_file=None,
            SECRET_KEY="test-secret",
            ENVIRONMENT="production",
            DEVELOPMENT_MODE=True,
        )


def test_dev_mode_in_development_is_allowed():
    s = Settings(
        _env_file=None,
        SECRET_KEY="test-secret",
        ENVIRONMENT="development",
        DEVELOPMENT_MODE=True,
    )
    assert s.DEVELOPMENT_MODE is True
    assert s.is_production is False


def test_production_without_dev_mode_is_allowed():
    s = Settings(
        _env_file=None,
        SECRET_KEY="test-secret",
        ENVIRONMENT="production",
        DEVELOPMENT_MODE=False,
    )
    assert s.is_production is True
