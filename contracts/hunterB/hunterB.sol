// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract HunterB is Initializable, UUPSUpgradeable, ERC20Upgradeable, ERC20PermitUpgradeable, ERC20VotesUpgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable{
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardHunterDebt; // Reward debt in Hunter.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Hunter
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accHunterPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accHunterPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20Upgradeable lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. Hunters to distribute per block.
        uint256 lastRewardBlock;  // Last block number that Hunters distribution occurs.
        uint256 accHunterPerShare; // Accumulated Hunters per share, times 1e12. See below.
        uint256 lastTotalHunterReward; // last total rewards
        uint256 lastHunterRewardBalance; // last Hunter rewards tokens
        uint256 totalHunterReward; // total Hunter rewards tokens
    }

    // The Hunter TOKEN!
    IERC20Upgradeable public Hunter;
    // admin address.
    address public adminAddress;
    // treasury address
    address public treasury;
    // address of ransom number generator
    address public numberGenerator;
    // Bonus multiplier for early Hunter makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // random threasold value
    uint256 public randomThreshold;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when reward distribution start.
    uint256 public startBlock;
    // total Hunter staked
    uint256 public totalHunterStaked;
    // total reward of mandators
    uint256 public totalRewardMandators;

    // mapping of total staked mandators
    mapping(uint256 => uint256) public totalStakedMandators;
    // mapping of total reward mandators
    mapping(uint256 => uint256) public totalHunterRewardMandators;

    // last full fill id
    uint256 public lastFulfilledId;
    // counter value of stakers
    uint256 public counter;
    // mapping of random words
    mapping(uint256 => uint256[]) public randomWords;
    // mapping of mandators with bool status
    mapping(uint256 => mapping(address => bool)) private is_mandator;
    // stake id of stakers mapping
    mapping(uint256 => address) public stakerId;
    // mapping of stakers with their ids
    mapping(address => uint256) public stakerAddressID;
    // mapping of stakers
    mapping(address => bool) public isStaker;
    // array of selected indexes
    uint256[] public selectedIndexes;
    // Generation started
    bool public isGenerationStarted;
    // constant hunter mander amount
    uint256 private _hunterMandatorStakeAmount;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event AdminUpdated(address newAdmin);
    event RandomNumber(uint256 _lastFullFillId, address _manders);
    event RandomNumberGeneratorUpdated(address _numberGenerator);
    event HunterMandatorsReward(uint256 lastFulfilledId, uint256 depositAmount);
    event UpdateRandomGenerationNumber(uint256 oldRandomThreshold, uint256 newRandomThreshold);
    event UpdateHunterMandatorStatus(uint256 _lastFullFillId, address _mander, bool status);

    /** 
      * @dev Throws if called by any account other than the treasury contract.
     */
    modifier onlyTreasury() {
        require(treasury == _msgSender(), "hunterB: caller is not the treasury");
        _;
    }

    /** 
      * @dev Throws if called by any account other than the random generation contract.
     */
    modifier onlyRandomNumGenerator() {
        require(numberGenerator == _msgSender(), "hunterB: caller is not the random generator contract");
        _;
    }
    
    /** 
      * @dev Throws if random generation not started.
     */
    modifier randomGenerationInProgress(){
        require(isGenerationStarted, "hunterB: Random generation not started");
        _;
    }

    /** 
      * @dev Throws if random generation in progress.
     */
    modifier randomGenerationCompleted(){
        require(!isGenerationStarted, "hunterB: Random generation in progress");
        _;
    }

    function initialize(        
        IERC20Upgradeable _hunter,
        address _adminAddress,
        address _treasury,
        uint256 _startBlock,
        uint256 _randomThreshold
        ) public initializer {
        require(_adminAddress != address(0), "initialize: Zero address");
        require(_treasury != address(0), "initialize: Zero address");
        require(address(_hunter) != address(0), "initialize: Zero address");
        OwnableUpgradeable.__Ownable_init();
        __ERC20_init_unchained("hunterB", "hunterB");
        __Pausable_init_unchained();
        __ReentrancyGuard_init();
        ERC20PermitUpgradeable.__ERC20Permit_init("hunterB");
        ERC20VotesUpgradeable.__ERC20Votes_init_unchained();
        Hunter = _hunter;
        adminAddress = _adminAddress;
        startBlock = _startBlock;
        randomThreshold = _randomThreshold;
        treasury = _treasury;
	    _hunterMandatorStakeAmount = 10 * 10**18;
    }

    // return pool lenagth
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20Upgradeable _lpToken, bool _withUpdate) external onlyOwner {
        require(address(_lpToken) != address(0), "add: Zero address");
        require(poolInfo.length < 1, "Cannot add more pool");
        _add(_allocPoint, _lpToken, _withUpdate);
    }

    function _add(uint256 _allocPoint, IERC20Upgradeable _lpToken, bool _withUpdate) internal {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accHunterPerShare: 0,
            lastTotalHunterReward: 0,
            lastHunterRewardBalance: 0,
            totalHunterReward: 0
        }));
    }
    
    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        if (_to >= _from) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else {
            return _from.sub(_to);
        }
    }
    
    // View function to see pending Hunters on frontend.
    function pendingHunter(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accHunterPerShare = pool.accHunterPerShare;
        uint256 lpSupply = totalHunterStaked;
        if(_pid != 0){
            lpSupply = totalStakedMandators[_pid];
        }
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 rewardBalance = pool.lpToken.balanceOf(address(this)).sub(totalHunterStaked).sub(totalRewardMandators);
            if(_pid != 0){
                rewardBalance = totalHunterRewardMandators[_pid];
            }
            uint256 _totalReward = rewardBalance.sub(pool.lastHunterRewardBalance);
            accHunterPerShare = accHunterPerShare.add(_totalReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accHunterPerShare).div(1e12).sub(user.rewardHunterDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public randomGenerationCompleted{
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 rewardBalance = pool.lpToken.balanceOf(address(this)).sub(totalHunterStaked).sub(totalRewardMandators);
        uint256 lpSupply = totalHunterStaked;
        if(_pid != 0){
            lpSupply = totalStakedMandators[_pid];
            rewardBalance = totalHunterRewardMandators[_pid];
        }
        uint256 _totalReward = pool.totalHunterReward.add(rewardBalance.sub(pool.lastHunterRewardBalance));
        pool.lastHunterRewardBalance = rewardBalance;
        pool.totalHunterReward = _totalReward;

        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            pool.accHunterPerShare = 0;
            pool.lastTotalHunterReward = 0;
            user.rewardHunterDebt = 0;
            pool.lastHunterRewardBalance = 0;
            pool.totalHunterReward = 0;
            return;
        }

        uint256 reward = _totalReward.sub(pool.lastTotalHunterReward);
        pool.accHunterPerShare = pool.accHunterPerShare.add(reward.mul(1e12).div(lpSupply));
        pool.lastTotalHunterReward = _totalReward;
    }

    // Deposit Hunter tokens to MasterChef.
    function deposit(uint256 _pid, uint256 _amount) external randomGenerationCompleted nonReentrant{
        require(_pid == 0,"Wrong pool Id");
        _deposit(_pid, msg.sender, _amount);

        if(iHunterMandator(msg.sender)){
            _deposit(lastFulfilledId, msg.sender, 0);
        }
    }

    function _deposit(uint256 _pid,address _userAddress, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_userAddress];
        updatePool(_pid);
        uint256 hunterReward;
        if (user.amount > 0) {
            hunterReward = user.amount.mul(pool.accHunterPerShare).div(1e12).sub(user.rewardHunterDebt);
            pool.lpToken.safeTransfer(_userAddress, hunterReward);
        }
        user.amount = user.amount.add(_amount);
        user.rewardHunterDebt = user.amount.mul(pool.accHunterPerShare).div(1e12);
        if(_pid == 0) {
            pool.lastHunterRewardBalance = pool.lpToken.balanceOf(address(this)).sub(totalHunterStaked).sub(totalRewardMandators);
            pool.lpToken.safeTransferFrom(address(_userAddress), address(this), _amount);
            totalHunterStaked = totalHunterStaked.add(_amount);
            _mint(_userAddress,_amount);
        } else {
            totalRewardMandators = totalRewardMandators.sub(hunterReward);
            totalHunterRewardMandators[_pid] = totalHunterRewardMandators[_pid].sub(hunterReward);
            pool.lastHunterRewardBalance = totalHunterRewardMandators[_pid];
            totalStakedMandators[_pid] = totalStakedMandators[_pid].add(_amount); 
        }
        emit Deposit(_userAddress, _pid, _amount);
    }

    // Withdraw Hunter tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external randomGenerationCompleted nonReentrant{
        require(_pid == 0,"Wrong pool Id");
        _withdraw(_pid,msg.sender,_amount);
        if(iHunterMandator(msg.sender)){
            UserInfo storage user = userInfo[_pid][msg.sender];
            if(user.amount == 0) {
                _withdraw(lastFulfilledId, msg.sender, _hunterMandatorStakeAmount);
                is_mandator[lastFulfilledId][msg.sender] = false;
                emit UpdateHunterMandatorStatus(lastFulfilledId, msg.sender, false);
            }
        }
    }

    function _withdraw(uint256 _pid,address _userAddress, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_userAddress];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);

        uint256 hunterReward = user.amount.mul(pool.accHunterPerShare).div(1e12).sub(user.rewardHunterDebt);
        pool.lpToken.safeTransfer(_userAddress, hunterReward);

        user.amount = user.amount.sub(_amount);
        user.rewardHunterDebt = user.amount.mul(pool.accHunterPerShare).div(1e12);
        if(_pid == 0){
            pool.lastHunterRewardBalance = pool.lpToken.balanceOf(address(this)).sub(totalHunterStaked).sub(totalRewardMandators);
            totalHunterStaked = totalHunterStaked.sub(_amount);
            pool.lpToken.safeTransfer(address(_userAddress), _amount);
            _burn(_userAddress,_amount);
        } else if(user.amount == 0) {
            totalRewardMandators = totalRewardMandators.sub(hunterReward);
            totalHunterRewardMandators[_pid] = totalHunterRewardMandators[_pid].sub(hunterReward);
            pool.lastHunterRewardBalance = totalHunterRewardMandators[_pid];
            totalStakedMandators[_pid] = totalStakedMandators[_pid].sub(_amount);
        }
        
        emit Withdraw(_userAddress, _pid, _amount);
    }
    
    // Earn Hunter tokens to MasterChef.
    function claimHunter(uint256 _pid) public randomGenerationCompleted nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        
        uint256 hunterReward = user.amount.mul(pool.accHunterPerShare).div(1e12).sub(user.rewardHunterDebt);
        pool.lpToken.safeTransfer(msg.sender, hunterReward);
        if(_pid == 0){
            pool.lastHunterRewardBalance = pool.lpToken.balanceOf(address(this)).sub(totalHunterStaked).sub(totalRewardMandators);
        } else {
            totalRewardMandators = totalRewardMandators.sub(hunterReward);
            totalHunterRewardMandators[_pid] = totalHunterRewardMandators[_pid].sub(hunterReward);
            pool.lastHunterRewardBalance = totalHunterRewardMandators[_pid];
        }
        
        user.rewardHunterDebt = user.amount.mul(pool.accHunterPerShare).div(1e12);
    }

    // Update admin address by the previous admin.
    function admin(address _adminAddress) public {
        require(_adminAddress != address(0), "admin: Zero address");
        require(msg.sender == adminAddress, "admin: wut?");
        adminAddress = _adminAddress;
        emit AdminUpdated(_adminAddress);
    }

    // update random number generation address
    function setRandomNumberGenerator(address _numberGenerator) public onlyOwner {
        require(_numberGenerator != address(0), "Invalid numberGenerator address");
        numberGenerator = _numberGenerator;
        emit RandomNumberGeneratorUpdated(_numberGenerator);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        updateUserAddress();
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        updateUserAddress();
        super._burn(account, amount);
    }

    // update stake id to each stakers
    function updateUserAddress() internal {
        UserInfo storage user = userInfo[0][msg.sender];
        if (user.amount > 0 && !isStaker[msg.sender]) {
            stakerId[counter] = msg.sender;
            stakerAddressID[msg.sender] = counter;
            isStaker[msg.sender] = true;
            counter = counter.add(1);
        } else if (user.amount == 0 && isStaker[msg.sender]) {
            uint256 tempId = stakerAddressID[msg.sender];
            address tempAddress = stakerId[counter.sub(1)];
            stakerId[tempId] = tempAddress;
            stakerAddressID[tempAddress] = tempId;
            stakerId[counter.sub(1)] = address(0);
            isStaker[msg.sender] = false;
            counter = counter.sub(1);
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        ERC20VotesUpgradeable._afterTokenTransfer(from, to, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        
        if(from == address(0) || to == address(0)){
            super._beforeTokenTransfer(from, to, amount);
        }else{
            revert("Non transferable token");
        }
    }

    function _delegate(address delegator, address delegatee) internal virtual override {
        super._delegate(delegator,delegatee);
    }

    // update hunter mandators reward only treasury contract can call this method
    function updateHunterMandatorsReward(uint256 _depositAmount) external onlyTreasury{
        Hunter.safeTransferFrom(treasury,address(this),_depositAmount);
        totalRewardMandators = totalRewardMandators.add(_depositAmount);
        totalHunterRewardMandators[lastFulfilledId] = totalHunterRewardMandators[lastFulfilledId].add(_depositAmount);
        emit HunterMandatorsReward(lastFulfilledId, _depositAmount);
    }

    // update random number generation threasold value
    function updateNumberOfRandomGeneration(uint256 _randomThreshold) external onlyOwner{
	    emit UpdateRandomGenerationNumber(randomThreshold, _randomThreshold);
        randomThreshold = _randomThreshold;
    }

    // return true if address is hunter mandator otherwise false
    function iHunterMandator(address _userAddress) public view returns(bool){
        return is_mandator[lastFulfilledId][_userAddress];
    }

    // initialize random address selection only random generation contract can call this method
    function initializeRandomAddressSelection(uint256 _lastFulfilledId, uint256[] memory _randomWords, address[] memory _nftOwners) external onlyRandomNumGenerator nonReentrant{
        require(_lastFulfilledId == poolInfo.length, "Configuration not matched");
        lastFulfilledId = _lastFulfilledId;
        randomWords[lastFulfilledId] = _randomWords;
        _add(100, Hunter, false);
        isGenerationStarted = true;
        uint256[] memory blankArray;
        selectedIndexes = blankArray;
        for(uint256 i =0; i < _nftOwners.length; i++ ){
            is_mandator[lastFulfilledId][_nftOwners[i]] = true;
            _deposit(lastFulfilledId,_nftOwners[i], _hunterMandatorStakeAmount);
        }
    }

    // generate random number with latest pool id.
    function randomSelectUsers(uint16 numberOfUsers) external randomGenerationInProgress nonReentrant{
        _randomSelectUsers(
            numberOfUsers,
            randomWords[lastFulfilledId][0],
            randomWords[lastFulfilledId][1]
        );
    }

    function _randomSelectUsers(
        uint16 numberOfUsers,
        uint256 one,
        uint256 two
    ) internal {
        uint256 value = two;
        for(uint256 i=0; i< numberOfUsers; i++){
            value =
                uint256(keccak256(abi.encodePacked(one, value)));
            uint256 tmpValue = value % counter;
            uint256 reps = value % 11;
            uint256 gapMod = numberOfUsers < 11 ? numberOfUsers : 11;
            uint256 gap = uint256(keccak256(abi.encodePacked(one, reps)))% gapMod ;
            for (uint256 j = 0; j< reps ; j++){
            if (
                !is_mandator[lastFulfilledId][stakerId[tmpValue]] &&
                stakerId[tmpValue] != address(0) &&
                selectedIndexes.length < randomThreshold &&
                tmpValue < counter
            ) {
                is_mandator[lastFulfilledId][stakerId[tmpValue]] = true;
                selectedIndexes.push(tmpValue);
                _deposit(lastFulfilledId, stakerId[tmpValue], _hunterMandatorStakeAmount);
                emit RandomNumber(lastFulfilledId, stakerId[tmpValue]);
            }
            tmpValue = tmpValue + gap;
            }
        }
        if(selectedIndexes.length == randomThreshold){
            isGenerationStarted = false;
        }
    }

    function _authorizeUpgrade(address) internal view override {
        require(owner() == msg.sender, "Only owner can upgrade implementation");
    }
}