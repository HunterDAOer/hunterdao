// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

interface IUniswapV2Router {
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function WETH() external pure returns (address);

    function factory() external pure returns (address);
}

contract InversteeDetailsStruct {
    struct InversteeDetails {
        address _investee;
        uint _fundAmount;
    }
}

interface IGovernance {
    function _fundInvestee() external returns(InversteeDetailsStruct.InversteeDetails memory);
    function nextInvesteeFund() external pure returns(uint256);
    function nextInvestee() external pure returns(uint256);
    function investeeDetails(uint256 _investeeId) external returns(InversteeDetailsStruct.InversteeDetails memory);
}

interface IHunterB {
    function updateHunterMandatorsReward(uint256 _reward) external;
}

contract HunterBTreasury is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMathUpgradeable for uint256;
    // Dead address to burn tokens
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    // address of hunter token
    address public hunter;
    // address of DAO contract
    address public dao;
    // address of hunterB token
    address public hunterB;
    // address of multisign wallet address
    address public multSignWallet;
    // address of exchange router
    address public router;
    // array path of weth and hunter
    address[] private path;
    // array path of hunter, weth, and usdc
    address[] private pathUSDC;
    // address of usdc token
    address public USDC;

    /**
      * @notice initialize params
      * @param _hunter address of hunter token
      * @param _router address of router contract
      * @param _usdc address of hunter token
      * @param _weth address of hunter token
      */
    function initialize(        
        address _hunter,
        address _router,
        address _usdc,
        address _weth
        ) public initializer {
        require(_hunter != address(0),"initialize: Invalid address");
        require(_usdc != address(0),"initialize: Invalid address");
        require(_router != address(0),"initialize: Invalid address");
        require(_weth != address(0), "initialize: Invalid address");
        hunter = _hunter;
        router = _router;
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        __Context_init_unchained();
        __Pausable_init_unchained();
        path.push(_weth);
        path.push(hunter);
        USDC = _usdc;
        pathUSDC.push(hunter);
        pathUSDC.push(_weth);
        pathUSDC.push(USDC);
    }

    function _authorizeUpgrade(address) internal view override {
        require(owner() == msg.sender, "Only owner can upgrade implementation");
    }

    /**
      * @notice Set DAO address
      * @param _dao The address of DAO 
      */
    function setDAOAddress(address _dao) external onlyOwner {
        require(_dao != address(0),"setDAOAddress: Invalid address");
        dao = _dao;
    }

    /**
      * @notice Set hunterB address
      * @param _hunterB The address of hunterB 
      */
    function sethunterBAddress(address _hunterB) external onlyOwner {
        require(_hunterB != address(0),"setDAOAddress: Invalid address");
        hunterB = _hunterB;
    }

    /**
      * @notice Set multiSign address
      * @param _multiSignAddress The address of multiSign 
      */
    function setMultiSignAddress(address _multiSignAddress) external onlyOwner {
        require(_multiSignAddress != address(0),"setMultiSignAddress: Invalid address");
        multSignWallet = _multiSignAddress;
    }

    /**
      * @notice return hunter price in usdc
      * @param _amount The amount of hunterB 
      */
    function hunterPriceInUSD(uint256 _amount) public view returns (uint256) {
        uint256[] memory hunterAmount = IUniswapV2Router(router).getAmountsOut(_amount, pathUSDC);
        return hunterAmount[2];
    }

    /**
      * @notice validatePayout used to distribute fund
      */
    function validatePayout() external {
        uint256 balance = IERC20Upgradeable(hunter).balanceOf(address(this));
        InversteeDetailsStruct.InversteeDetails memory investee = IGovernance(dao).investeeDetails(IGovernance(dao).nextInvesteeFund());
        if(investee._investee != address(0) && investee._fundAmount == 0) {
            InversteeDetailsStruct.InversteeDetails memory investee = IGovernance(dao)._fundInvestee();
        }
        if(balance > 0 && investee._fundAmount != 0) {
            uint256[] memory getHunterAmountOneETH = IUniswapV2Router(router).getAmountsOut(investee._fundAmount, path);
            if((IGovernance(dao).nextInvesteeFund()<IGovernance(dao).nextInvestee()) && balance >= getHunterAmountOneETH[1]){
                fundInvestee(getHunterAmountOneETH[1]);
            }
        }
    }

    function fundInvestee(uint256 totalAmount) internal nonReentrant{
        InversteeDetailsStruct.InversteeDetails memory investee = IGovernance(dao)._fundInvestee();
        IERC20Upgradeable(hunter).transfer(DEAD_ADDRESS, totalAmount.mul(30).div(100));
        IERC20Upgradeable(hunter).transfer(investee._investee, totalAmount.mul(40).div(100));
        IERC20Upgradeable(hunter).transfer(hunterB, totalAmount.mul(25).div(100));
        IERC20Upgradeable(hunter).approve(hunterB, totalAmount.mul(5).div(100));
        IHunterB(hunterB).updateHunterMandatorsReward(totalAmount.mul(5).div(100));
    }
}

