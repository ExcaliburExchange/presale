// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

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

    EnumerableSet.AddressSet refs;

    uint256 refAllocation; // allocation earned by referring another user
    uint256 refEarning; // WFTM earned by referring another user
    bool getAllocationAsRef; // define the user earn allocation or WFTM by referring another user
    uint256 refShare;

    bool hasClaimed; // has already claim its lp share
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
  uint256 public constant DEFAULT_MAX_ALLOCATION = 300 ether; // 300FTM
  uint256 public constant REFERRER_MIN_ALLOCATION = 0 ether; // min allocation to have to be able to referrer another users

  uint256 public totalAllocation;
  uint256 totalLPAmountToClaim;

  uint256 public lpWFTMAmount;
  bool public isLpBuilt;


  constructor(address exc, address wftm, IExcaliburV2Factory factory, IDividends dividends, uint256 startTime, uint256 endTime) {
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
    refAllocation = user.refAllocation;
    refEarning = user.refEarning;
    getAllocationAsRef = user.getAllocationAsRef;
    refShare = user.refShare;
    hasClaimed = user.hasClaimed;
  }

  /****************************************************************/
  /****************** EXTERNAL PUBLIC FUNCTIONS  ******************/
  /****************************************************************/

  function buy(address referralAddress) external payable isSaleActive {
    uint256 ftmAmount = msg.value;

    require(ftmAmount > 0, "buy: zero amount");

    userInfo storage user = users[msg.sender];
    uint256 maxAllocation = user.maxAllocation != 0 ? user.maxAllocation : DEFAULT_MAX_ALLOCATION;

    require(user.allocation.add(ftmAmount) <= maxAllocation, "buy: total amount cannot exceed maxAllocation");

    if(user.allocation == 0 && user.refs.length() == 0 && referralAddress != address(0)){
      // If first buy, and does not have any ref already set
      if(users[referralAddress].allocation > REFERRER_MIN_ALLOCATION ) user.refs.add(referralAddress);
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
          assert(IWETH(WFTM).transfer(curRefAddress, refShareAmount));
        }
      }
    }

    user.allocation = user.allocation.add(ftmAmount);
    totalAllocation = totalAllocation.add(ftmAmount);
    lpWFTMAmount = lpWFTMAmount.add(ftmAmount.div(2));

    IWETH(WFTM).deposit{value : ftmAmount}();

    emit Buy(msg.sender, ftmAmount);
  }

  function claim() external isClaimable {
    userInfo storage user = users[msg.sender];

    require(totalAllocation > 0 && user.allocation > 0, "claim: zero allocation");
    require(!user.hasClaimed, "claim: already claimed");
    user.hasClaimed = true;

    uint256 LPAmountToClaim = user.allocation.add(user.refAllocation).mul(totalLPAmountToClaim).div(totalAllocation);
    IERC20(lpToClaim).safeTransfer(msg.sender, LPAmountToClaim);

    emit Claim(msg.sender, LPAmountToClaim);
  }

  /****************************************************************/
  /********************** OWNABLE FUNCTIONS  **********************/
  /****************************************************************/

  function buildLP() external virtual onlyOwner {
    require(hasEnded(), "buildLP: sale has not ended");
    isLpBuilt = true;

    lpToClaim = FACTORY.getPair(EXC, WFTM);
    uint256 excAmount = IERC20(EXC).balanceOf(address(this));
    IERC20(EXC).safeTransfer(lpToClaim, excAmount);
    IERC20(WFTM).safeTransfer(lpToClaim, lpWFTMAmount);
    totalLPAmountToClaim = IExcaliburV2Pair(lpToClaim).mint(address(this));

    // add remaining WFTM to dividends
    DIVIDENDS.addDividendsToPending(WFTM, IERC20(WFTM).balanceOf(address(this)));

    emit LPBuild(excAmount, lpWFTMAmount);
  }

  /********************************************************/
  /****************** INTERNAL FUNCTIONS ******************/
  /********************************************************/

  /**
   * @dev Utility function to get the current block timestamp
   */
  function _currentBlockTimestamp() internal view virtual returns (uint256) {
    return block.timestamp;
  }
}