"""Authentication endpoints.

Provides login endpoint for JWT token generation.
"""

from fastapi import APIRouter, HTTPException, status, Depends
from fastapi.security import OAuth2PasswordRequestForm
from datetime import timedelta
from ..config import (
    get_auth_method,
    get_jwt_secret_key,
    get_jwt_algorithm,
    get_jwt_expiration_minutes,
    get_jwt_test_users,
    AuthMethod,
)
from ..auth import create_access_token, verify_test_user

router = APIRouter(prefix="/auth", tags=["authentication"])


@router.post("/login")
async def login(form_data: OAuth2PasswordRequestForm = Depends()):
    """
    JWT login endpoint for test users (development only).

    Args:
        form_data: OAuth2 password request form (username + password)

    Returns:
        dict: Access token and token type

    Raises:
        HTTPException: 400 if JWT auth not enabled
        HTTPException: 401 if credentials are invalid
    """
    auth_method = get_auth_method()

    if auth_method != AuthMethod.JWT:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="JWT authentication not enabled (AUTH_METHOD != jwt)",
        )

    # Verify credentials against test users
    test_users = get_jwt_test_users()
    if not verify_test_user(form_data.username, form_data.password, test_users):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Generate JWT token
    secret_key = get_jwt_secret_key()
    algorithm = get_jwt_algorithm()
    expiration_minutes = get_jwt_expiration_minutes()

    access_token_expires = timedelta(minutes=expiration_minutes)
    access_token = create_access_token(
        data={"sub": form_data.username},
        secret_key=secret_key,
        algorithm=algorithm,
        expires_delta=access_token_expires,
    )

    return {"access_token": access_token, "token_type": "bearer"}
