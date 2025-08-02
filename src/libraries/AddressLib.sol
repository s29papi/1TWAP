// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

type Address is uint160;

library AddressLib {
    function toAddress(Address a) internal pure returns (address) {
        return address(uint160(Address.unwrap(a)));
    }

    function fromAddress(address a) internal pure returns (Address) {
        return Address.wrap(uint160(a));
    }
}
