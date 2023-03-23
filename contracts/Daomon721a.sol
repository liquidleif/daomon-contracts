// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "erc721a-upgradeable/contracts/ERC721AUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

/**
 * @dev The Interface might change depending on the final metadata definition and source.
 */
interface ITokenURIProvider {
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

// @todo Check if we move parts to interfaces, libs and abstract contracts.
// @todo Add tests
contract Daomon721a is
    ERC721AUpgradeable,
    OwnableUpgradeable,
    AccessControlEnumerableUpgradeable
{
    // =============================================================
    //                        ACCESS CONTROL
    // =============================================================
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // =============================================================
    //                        DEFINITIONS
    // =============================================================

    error TokenNotMinted(uint256 tokenId);
    error TokenIsLocked(uint256 tokenId);
    error NotOwnerOfToken(uint256 tokenId);
    error NoTokenURIProviderSet();

    /**
     * @notice store all lock infos per token. We use this to avoid storing init all
     *         data per token on mint.
     * @dev If no lock info is set, the token is locked with deployment time per default.
     *
     * @todo Maybe we change this to atomic mappings later in dev process. For now this
     *       is sufficient. And we might merge start time and totalTime into one uint256
     *       to store gas. But this is not a big deal.
     */
    struct LockInfo {
        // 0 = token is not locked.
        uint256 startTime;
        // Cumulative per-token locking time. Will be reduced per unlock. And only updated on request. Like current
        // locking time getter or unlock.
        uint256 totalTime;
    }

    // =============================================================
    //                        STORAGE
    // =============================================================

    /**
     * @notice Metadata generator contract proxy.
     * @dev If not set, the tokenURI will revert. If you just want to use the baseUri approach
     *      add a contract that returns the baseUri.
     */
    ITokenURIProvider internal tokenUriProvider;

    /**
     * @dev this is the deployment time. We use this as the default lock time for all tokens.
     *      So we do not have to init data for all tokens on mint.
     *      and we can leverage the improvement of the ERC721a standard to save gas.
     **/
    uint256 internal deploymentTimeStamp = block.timestamp;

    /**
     * @notice store all lock infos per token. We use this to avoid storing init all. If not
     *         set the token is locked with deployment time.
     * @dev Best use _getLockInfo() to access this mapping. This will take care of minted check
     *      and will return a default with deployment time if no lock info is set.
     */
    mapping(uint256 => LockInfo) internal lockInfo;

    /**
     * @notice this is the precision of the penalty percentage. So if 10000 is 100% or 200 is 100%
     */
    uint32 public constant unlockPenatlyPercentagePrecision = 10_000;
    // 0 % unlock penalty as default. If set to 0, no penalty will be applied.
    uint32 unlockPenaltyPercentage = 0;

    // =============================================================
    //                        Modifiers
    // =============================================================

    /**
     * @notice Modifier to check if token is minted.
     */
    modifier isMinted(uint256 tokenId) {
        if (!_exists(tokenId)) revert TokenNotMinted(tokenId);
        _;
    }

    /**
     * @notice Modifier to check if token is locked.
     */
    modifier isLocked(uint256 tokenId) {
        if (!isTokenLocked(tokenId)) revert NotOwnerOfToken(tokenId);
        _;
    }

    /**
     * @notice Modifier to check if request is coming from a manager address.
     */
    modifier onlyManager() {
        require(
            hasRole(MANAGER_ROLE, msg.sender),
            "Caller does not have the required role"
        );
        _;
    }

    // =============================================================
    //                        CONFIGURATION
    // =============================================================

    /**
     * Initialize the contract.
     *
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     * @param _tokenUriProvider The tokenURI provider contract which will create the metadata for a token.
     * @param _unlockPenaltyPercentage The unlock penalty percentage. 0 = no penalty. 10000 = 100% and the minimal penalty is 1 = 0.01 % penalty.
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        ITokenURIProvider _tokenUriProvider,
        uint32 _unlockPenaltyPercentage
    ) public initializerERC721A initializer {
        // set roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);

        // configure the storage
        tokenUriProvider = _tokenUriProvider;
        deploymentTimeStamp = block.timestamp;
        unlockPenaltyPercentage = _unlockPenaltyPercentage;

        // innit all other upgradable contracts
        __ERC721A_init(_name, _symbol);
        __Ownable_init();
        __AccessControlEnumerable_init();
    }

    /**
     * @notice Sets the optional tokenURI override contract.
     */
    function setRenderingContract(
        ITokenURIProvider _tokenUriProvider
    ) external onlyManager {
        require(address(_tokenUriProvider) != address(0), "Invalid address");
        tokenUriProvider = _tokenUriProvider;
    }

    /**
     * @notice Sets the unlock penalty percentage.
     */
    function setUnlockPenaltyPercentage(
        uint32 _unlockPenaltyPercentage
    ) external onlyManager {
        require(_unlockPenaltyPercentage >= 0, "Penalty must be >= 0");
        unlockPenaltyPercentage = _unlockPenaltyPercentage;
    }

    // =============================================================
    //                        WRITES
    // =============================================================

    function toggleLock(uint256 tokenId) public {
        if (ownerOf(tokenId) != msg.sender) revert NotOwnerOfToken(tokenId);

        // if the token is locked, unlock it and update the total lock time
        if (isTokenLocked(tokenId)) {
            lockInfo[tokenId].totalTime = _sanitizeInfo(_getLockInfo(tokenId))
                .totalTime;
            lockInfo[tokenId].startTime = 0;

            assert(!isTokenLocked(tokenId));
        } else {
            lockInfo[tokenId].startTime = block.timestamp;
            uint256 penalty = _getPenalty(lockInfo[tokenId].totalTime);
            if (penalty <= lockInfo[tokenId].totalTime) {
                lockInfo[tokenId].totalTime -= penalty;
            } else {
                lockInfo[tokenId].totalTime = 0;
            }

            assert(isTokenLocked(tokenId));
        }
    }

    // =============================================================
    //                        VIEWS
    // =============================================================

    /**
     * @notice Returns the lock start time for a token.
     * @param tokenId The token id to check if it is locked.
     * @dev This function will return false if the token is not locked. A token is defined
     *      as locked if the lock start time is > 0. So if not set it is unlocked.
     */
    function isTokenLocked(uint256 tokenId) public view returns (bool) {
        return getLockStartTime(tokenId) > 0;
    }

    function getLockStartTime(uint256 tokenId) public view returns (uint256) {
        return _getLockInfo(tokenId).startTime;
    }

    function getTokenTotalLockTime(
        uint256 tokenId
    ) public view returns (uint256) {
        // use a virtual up to date clone here to have the newest value
        return _getUpToDateLockInfoClone(tokenId).totalTime;
    }

    /**
     * @param tokenId  The token id to get the lock info for.
     * @notice This function will return the lock info for a token.
     *         It will return an up to date value based on the current
     *         block time.
     */
    function getLockInfo(
        uint256 tokenId
    ) public view returns (LockInfo memory) {
        // use a virtual up to date clone here to have the newest value
        return _getUpToDateLockInfoClone(tokenId);
    }

    // =============================================================
    //                        OVERRIDES
    // =============================================================

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        super._beforeTokenTransfers(from, to, startTokenId, quantity);

        // if we mint, we do not need to check anything.
        if (from == address(0)) return;

        // Check if token or any of the tokens after startTokeId is locked and revert if so.
        // we have to check multiple as we use ERC721A and can transfer multiple tokens at once.
        uint256 end = startTokenId + quantity;
        for (uint256 i = startTokenId; i < end; i++) {
            if (isTokenLocked(i)) revert TokenIsLocked(i);
        }
    }

    /**
     * @notice Return all nft as on chain rendered metadata.
     * @return value, OpenSea conform metadata for the given token.
     */
    function tokenURI(
        uint256 tokenId
    ) public view override isMinted(tokenId) returns (string memory) {
        if (address(tokenUriProvider) == address(0)) {
            revert NoTokenURIProviderSet();
        }

        return tokenUriProvider.tokenURI(tokenId);
    }

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

    // =============================================================
    //                        INTERNAL UTILS
    // =============================================================

    function _getPenalty(
        uint256 totalLockTime
    ) internal view returns (uint256) {
        // if no penalty is set, return 0
        if (unlockPenaltyPercentage == 0) return 0;

        // If the total lock time is smaller than the precision, we do return the whole rest as penalty.
        // So the total time is 0 in the end.
        if (
            totalLockTime * unlockPenaltyPercentage <
            unlockPenatlyPercentagePrecision
        ) {
            return totalLockTime;
        }

        // calculate the penalty
        uint256 penalty = (totalLockTime * unlockPenaltyPercentage) /
            unlockPenatlyPercentagePrecision;

        // return the penalty
        return penalty;
    }

    function _lockInfoExists(uint256 tokenId) internal view returns (bool) {
        return
            lockInfo[tokenId].startTime > 0 || lockInfo[tokenId].totalTime > 0;
    }

    /**
     * @param tokenId  The token id to get the lock info for.
     * @notice This function will return the lock info for a token. It will always return a valid lock info if the token is minted.
     */
    function _getLockInfo(
        uint256 tokenId
    ) public view returns (LockInfo memory) {
        if (_exists(tokenId) == false) revert TokenNotMinted(tokenId);

        // either one is always set use the stored info.
        if (_lockInfoExists(tokenId)) {
            return lockInfo[tokenId];
        }

        return
            LockInfo(
                deploymentTimeStamp,
                block.timestamp - deploymentTimeStamp
            );
    }

    /**
     * @param tokenId  The token id to get the lock info for.
     * @notice This function will return the lock info for a token.
     *         The return value is a clone of the lock info with
     *         updated total lock time. This can be used for view functions.
     */
    function _getUpToDateLockInfoClone(
        uint256 tokenId
    ) internal view returns (LockInfo memory clone) {
        LockInfo memory info = _getLockInfo(tokenId);

        clone.startTime = info.startTime;
        clone.totalTime = info.totalTime;

        return _sanitizeInfo(clone);
    }

    /**
     * @param info The lock info to sanitize.
     * @notice This function will sanitize the lock info. It will update the total lock time and set the start time to the current block timestamp.
     */
    function _sanitizeInfo(
        LockInfo memory info
    ) internal view returns (LockInfo memory) {
        // this should never happen but we check it anyway
        if (info.startTime > block.timestamp) {
            info.startTime = block.timestamp;
        }

        info.totalTime += block.timestamp - info.startTime;

        return info;
    }
}
