import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";

interface Daomon721a {
    function mint(address to, uint256 amount) external;
}

contract Minter is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    error NoPurchasableTokens();
    error ZeroAmountNotAllowed();
    error NotEnoughMintableTokensForThisUser();
    error ReceiverNotWhitelisted();

    // User variables
    uint256 public numOfPurchasedTokens;
    mapping(address => uint256) public numOfMintableTokensPerAddress;

    // Admin variables
    uint256 public deploymentTimeStamp;
    uint256 public priceInPMON;
    uint256 public dailySupply;
    address public pmonAddress;
    address public pmonReceiverAddress;
    address public daomon721aAddress;
    bytes32 public merkleRoot;

    function initialize(
        address _pmonReceiverAddress,
        address _daomon721aAddress,
        bytes32 _merkleRoot
    ) public initializer {
        deploymentTimeStamp = block.timestamp;
        dailySupply = 10;
        priceInPMON = 10e18;
        pmonAddress = 0x1796ae0b0fa4862485106a0de9b654eFE301D0b2;
        pmonReceiverAddress = _pmonReceiverAddress;
        daomon721aAddress = _daomon721aAddress;
        merkleRoot = _merkleRoot;

        __Ownable_init();
    }

    function purchaseTo(
        address to,
        uint256 amount,
        bytes32[] calldata proof
    ) external {
        /* Checks */
        if (getNumOfPurchasableTokens() - amount <= 0)
            revert NoPurchasableTokens();
        if (amount <= 0) revert ZeroAmountNotAllowed();

        bytes32 leaf = keccak256(abi.encodePacked(to));
        if (!MerkleProofUpgradeable.verifyCalldata(proof, merkleRoot, leaf))
            revert ReceiverNotWhitelisted();

        /* Effects */
        numOfPurchasedTokens += amount;
        numOfMintableTokensPerAddress[to] += amount;

        /* Interactions */
        IERC20Upgradeable(pmonAddress).safeTransferFrom(
            msg.sender,
            pmonReceiverAddress,
            priceInPMON * amount
        );
    }

    function mint(address user, uint256 amount) external {
        /* Checks */
        if (numOfMintableTokensPerAddress[user] - amount < 0)
            revert NotEnoughMintableTokensForThisUser();

        /* Effects */
        numOfMintableTokensPerAddress[user] -= amount;

        /* Interactions */
        Daomon721a(daomon721aAddress).mint(user, amount);
    }

    /* 
    VIEW METHODS
    */

    function getNumOfPurchasableTokens() public view returns (uint256) {
        return
            ((block.timestamp - deploymentTimeStamp) / 1 days) *
            dailySupply -
            numOfPurchasedTokens;
    }

    /*
    OWNER METHODS
    */
    function setPriceInPMON(uint256 newPriceInPMON) public onlyOwner {
        priceInPMON = newPriceInPMON;
    }

    function setDailySupply(uint256 newDailySupply) public onlyOwner {
        dailySupply = newDailySupply;
    }

    function setPmonReceiverAddress(
        address newPmonReceiverAddress
    ) public onlyOwner {
        pmonReceiverAddress = newPmonReceiverAddress;
    }

    function setPmonAddress(address newPmonAddress) public onlyOwner {
        pmonAddress = newPmonAddress;
    }
}
