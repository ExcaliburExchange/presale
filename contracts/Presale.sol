// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "excalibur-core/contracts/interfaces/IExcaliburV2Pair.sol";
import "excalibur-core/contracts/interfaces/IExcaliburV2Factory.sol";
import "excalibur/contracts/interfaces/IDividends.sol";

import "./interfaces/IWETH.sol";

/**
  Excalibur presale contract
*/
contract Presale is Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  struct userInfo{
    uint256 allocation;
    uint256 maxAllocation;

    EnumerableSet.AddressSet refs; // allow to set multiple refs (same addr from multiple wl partners)

    uint256 refAllocation; // commissioned allocation earned by referring another user
    uint256 refEarning; // WFTM earned by referring another user
    bool getAllocationAsRef; // defines whether user will earn LP tokens or WFTM as a referrer
    uint256 refShare;

    bool hasClaimed; // has already claimed its lp share
  }

  mapping(address => userInfo) users;

  address public immutable EXC;
  address public immutable WFTM;
  address public lpToClaim;
  IExcaliburV2Factory public immutable FACTORY;
  IDividends public immutable DIVIDENDS;

  uint256 public immutable START_TIME;
  uint256 public immutable END_TIME;

  uint256 public constant DEFAULT_REFERRAL_SHARE = 3; // 3%
  uint256 public constant DEFAULT_MAX_ALLOCATION = 526 ether; // 526FTM ~$1k

  uint256 public totalAllocation;
  uint256 public totalLPAmountToClaim;

  uint256 public lpWFTMAmount;
  bool public isLpBuilt;

  address emergencyOperator; // Multisig operator with publicly known partners

  constructor(address exc, address wftm, IExcaliburV2Factory factory, IDividends dividends, uint256 startTime, uint256 endTime) {
    require(startTime < endTime, "invalid timestamp");

    EXC = exc;
    WFTM = wftm;
    FACTORY = factory;
    DIVIDENDS = dividends;
    START_TIME = startTime;
    END_TIME = endTime;
  }

  /********************************************/
  /****************** EVENTS ******************/
  /********************************************/

  event Buy(address indexed user, uint256 ftmAmount);
  event Claim(address indexed user, uint256 lpAmount);
  event LPBuild(uint256 excAmount, uint256 ftmAmount);
  event NewRefEarning(address referrer, uint256 ftmAmount);

  event TransferEmergencyOperator(address prevOperator, address newOperator);
  event EmergencyWithdraw(uint256 excAmount, uint256 ftmAmount);

  /***********************************************/
  /****************** MODIFIERS ******************/
  /***********************************************/

  modifier isSaleActive() {
    require(hasStarted() && !hasEnded(), "isActive: sale is not active");
    _;
  }

  modifier isClaimable(){
    require(hasEnded() && isLpBuilt, "isClaimable: sale has not ended");
    _;
  }

  /**************************************************/
  /****************** PUBLIC VIEWS ******************/
  /**************************************************/

  /**
  * @dev get remaining time before the end of the presale
  */
  function getRemainingTime() external view returns (uint256){
    if(hasEnded()) return 0;
    return END_TIME.sub(_currentBlockTimestamp());
  }

  /**
  * @dev get user share times 1e5
  */
  function getUserShare(address user) external view returns (uint256) {
    return users[user].allocation.mul(1e5).div(totalAllocation);
  }

  function hasStarted() public view returns (bool) {
    return _currentBlockTimestamp() >= START_TIME;
  }

  function hasEnded() public view returns (bool){
    return END_TIME <= _currentBlockTimestamp();
  }

  /**
  * @dev users getter
  */
  function getUserInfo(address userAddress) public view returns(uint256 allocation, uint256 maxAllocation, uint256 refAllocation,
    uint256 refEarning, bool getAllocationAsRef, uint256 refShare, bool hasClaimed) {
    userInfo storage user = users[userAddress];
    allocation = user.allocation;
    maxAllocation = user.maxAllocation;
    if(maxAllocation == 0) maxAllocation = DEFAULT_MAX_ALLOCATION;
    refAllocation = user.refAllocation;
    refEarning = user.refEarning;
    getAllocationAsRef = user.getAllocationAsRef;
    refShare = user.refShare;
    if(refShare == 0) refShare = DEFAULT_REFERRAL_SHARE;
    hasClaimed = user.hasClaimed;
  }

  /****************************************************************/
  /****************** EXTERNAL PUBLIC FUNCTIONS  ******************/
  /****************************************************************/

  function buy(address referralAddress) external payable isSaleActive {
    uint256 ftmAmount = msg.value;
    require(ftmAmount > 0, "buy: zero amount");

    IWETH(WFTM).deposit{value : ftmAmount}();

    userInfo storage user = users[msg.sender];
    uint256 maxAllocation = user.maxAllocation != 0 ? user.maxAllocation : DEFAULT_MAX_ALLOCATION;
    require(user.allocation.add(ftmAmount) <= maxAllocation, "buy: total amount cannot exceed maxAllocation");

    if(user.allocation == 0 && user.refs.length() == 0 && referralAddress != address(0) && referralAddress != msg.sender){
      // If first buy, and does not have any ref already set
      user.refs.add(referralAddress);
    }

    uint256 refsAmount = user.refs.length();
    if(refsAmount > 0){
      for (uint256 index = 0; index < refsAmount; ++index) {
        address curRefAddress = user.refs.at(index);
        userInfo storage referral = users[curRefAddress];
        uint256 refShare = referral.refShare != 0 ? referral.refShare : DEFAULT_REFERRAL_SHARE;
        refShare = refShare.div(refsAmount);
        uint256 refShareAmount = refShare.mul(ftmAmount).div(100);

        if(referral.getAllocationAsRef) {
          referral.refAllocation = referral.refAllocation.add(refShareAmount);
          totalAllocation = totalAllocation.add(refShareAmount);
          lpWFTMAmount = lpWFTMAmount.add(refShareAmount.div(2));
        }
        else{
          IERC20(WFTM).safeTransfer(curRefAddress, refShareAmount);
          emit NewRefEarning(curRefAddress, refShareAmount);
        }
      }
    }

    user.allocation = user.allocation.add(ftmAmount);
    totalAllocation = totalAllocation.add(ftmAmount);
    lpWFTMAmount = lpWFTMAmount.add(ftmAmount.div(2));

    emit Buy(msg.sender, ftmAmount);
  }

  function claim() external isClaimable {
    userInfo storage user = users[msg.sender];

    require(totalAllocation > 0 && user.allocation > 0, "claim: zero allocation");
    require(!user.hasClaimed, "claim: already claimed");
    user.hasClaimed = true;

    uint256 LPAmountToClaim = user.allocation.add(user.refAllocation).mul(totalLPAmountToClaim).div(totalAllocation);
    _safeClaimTransfer(msg.sender, LPAmountToClaim, IERC20(lpToClaim));

    emit Claim(msg.sender, LPAmountToClaim);
  }

  /****************************************************************/
  /********************** OWNABLE FUNCTIONS  **********************/
  /****************************************************************/

  struct allocationSettings{
    address account;
    uint256 maxAllocation;
  }
  /**
    @dev For custom allocations, used for launch partners users
    @param referrer: launch partner address
  */
  function setUsersAllocation(allocationSettings[] memory _users, address referrer) public onlyOwner {
    for (uint256 i = 0; i < _users.length; ++i){
      allocationSettings memory userAllocation = _users[i];
      userInfo storage user = users[userAllocation.account];
      if(user.maxAllocation < userAllocation.maxAllocation) user.maxAllocation = userAllocation.maxAllocation;
      user.refs.add(referrer);
    }
  }

  function setPartnerCommission(address account, uint256 refShare) public onlyOwner {
    require(refShare <= 5, 'invalid share');
    users[account].refShare = refShare;
    users[account].getAllocationAsRef = true;
  }

  function buildLP() external virtual onlyOwner {
    require(hasEnded(), "buildLP: sale has not ended");
    isLpBuilt = true;

    lpToClaim = FACTORY.getPair(EXC, WFTM);
    uint256 excAmount = IERC20(EXC).balanceOf(address(this));

    IERC20(EXC).safeTransfer(lpToClaim, excAmount);
    IERC20(WFTM).safeTransfer(lpToClaim, lpWFTMAmount);
    totalLPAmountToClaim = IExcaliburV2Pair(lpToClaim).mint(address(this));

    // add remaining WFTM to GRAIL dividends contract
    IERC20(WFTM).safeApprove(address(DIVIDENDS), IERC20(WFTM).balanceOf(address(this)));
    DIVIDENDS.addDividendsToPending(WFTM, IERC20(WFTM).balanceOf(address(this)));

    emit LPBuild(excAmount, lpWFTMAmount);
  }

  function initEmergencyOperator(address operator) external onlyOwner{
    require(emergencyOperator == address(0), "initEmergencyOperator: already initialized");
    emergencyOperator = operator;
    emit TransferEmergencyOperator(address(0), emergencyOperator);
  }

  /********************************************************/
  /****************** /!\ EMERGENCY ONLY ******************/
  /********************************************************/

  /**
  * @dev Failsafe
  *
  * Only callable by the multisig emergencyOperator
  */
  function emergencyWithdrawFunds() external {
    require(msg.sender == emergencyOperator, "emergencyWithdrawFunds: not allowed");
    uint256 wFTMAmount = IERC20(WFTM).balanceOf(address(this));
    uint256 excAmount = IERC20(EXC).balanceOf(address(this));
    IERC20(EXC).safeTransfer(msg.sender, excAmount);
    IERC20(WFTM).safeTransfer(msg.sender, wFTMAmount);

    emit EmergencyWithdraw(excAmount, wFTMAmount);
  }

  /********************************************************/
  /****************** INTERNAL FUNCTIONS ******************/
  /********************************************************/

  /**
   * @dev Safe token transfer function, in case rounding error causes contract to not have enough tokens
   */
  function _safeClaimTransfer(address to, uint256 amount, IERC20 lpToken) internal {
    uint256 lpTokenBalance = lpToken.balanceOf(address(this));
    bool transferSuccess = false;
    if (amount > lpTokenBalance) {
      transferSuccess = lpToken.transfer(to, lpTokenBalance);
    } else {
      transferSuccess = lpToken.transfer(to, amount);
    }
    require(transferSuccess, "safeClaimTransfer: Transfer failed");
  }

  /**
   * @dev Utility function to get the current block timestamp
   */
  function _currentBlockTimestamp() internal view virtual returns (uint256) {
    return block.timestamp;
  }
}