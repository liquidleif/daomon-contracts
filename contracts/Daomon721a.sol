// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "erc721a-upgradeable/contracts/ERC721AUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

contract Daomon721a is
    ERC721AUpgradeable,
    OwnableUpgradeable,
    AccessControlEnumerableUpgradeable
{
    error NotOwner();

    /* 
    INITIALIZER
    */
    function initialize() public initializerERC721A initializer {
        __ERC721A_init("Daomon", "DAOMON");
        __Ownable_init();
        __AccessControlEnumerable_init();
    }

    /*
    WRITE METHODS
    */

    function toggleLock(uint256 tokenId, uint256 secondsToLock) public {
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
    }

    /*
    VIEW METHODS
    */

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC721AUpgradeable, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /*
    OVERRIDE METHODS
    */
}
