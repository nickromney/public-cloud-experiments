"""Pydantic models for subnet calculator API."""

from pydantic import BaseModel, Field
from typing import Optional


class SubnetIPv4Request(BaseModel):
    """Request model for IPv4 subnet calculation."""

    network: str = Field(
        ..., description="IPv4 network in CIDR notation (e.g., 192.168.1.0/24)"
    )
    mode: str = Field(
        default="Azure", description="Cloud provider mode: Azure, AWS, OCI, or Standard"
    )


class SubnetIPv4Response(BaseModel):
    """Response model for IPv4 subnet calculation."""

    network: str
    mode: str
    network_address: str
    broadcast_address: Optional[str]
    netmask: str
    wildcard_mask: str
    prefix_length: int
    total_addresses: int
    usable_addresses: int
    first_usable_ip: str
    last_usable_ip: str
    note: Optional[str] = None


class SubnetIPv6Request(BaseModel):
    """Request model for IPv6 subnet calculation."""

    network: str = Field(
        ..., description="IPv6 network in CIDR notation (e.g., 2001:db8::/64)"
    )


class SubnetIPv6Response(BaseModel):
    """Response model for IPv6 subnet calculation."""

    network: str
    network_address: str
    prefix_length: int
    total_addresses: str  # Too large for int
    note: Optional[str] = None


class ValidateRequest(BaseModel):
    """Request model for IP address validation."""

    address: str = Field(..., description="IP address or CIDR notation")
