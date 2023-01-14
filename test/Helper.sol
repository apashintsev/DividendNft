// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "forge-std/console.sol";

contract Helper {
    function memcmp(bytes memory a, bytes memory b)
        internal
        pure
        returns (bool)
    {
        return (a.length == b.length) && (keccak256(a) == keccak256(b));
    }

    function strcmp(string memory a, string memory b)
        internal
        pure
        returns (bool)
    {
        return memcmp(bytes(a), bytes(b));
    }
}

contract Receiver is IERC721Receiver {
    mapping(address => uint256) received;

    function onERC721Received(
        address operator,
        address from,
        uint256 id,
        bytes calldata data
    ) external override returns (bytes4) {
        string memory log = string(
            abi.encodePacked(
                "operator:",
                operator,
                ";from:",
                from,
                "; id",
                id,
                "cd:",
                data
            )
        );
        console.log(log);
        received[from] = id;
        return this.onERC721Received.selector;
    }
}
