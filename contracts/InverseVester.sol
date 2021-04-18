// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IInv.sol";

/**
 * @title Inverse token vesting contract
 * @author Inverse Finance
 * @notice Contract for vesting agreement on INV tokens
 * @dev    Vesting calculation is linear
 */
contract InverseVester is Ownable {
    using SafeERC20 for IInv;

    uint256 public constant DAY = 1 days;

    /// @dev Timestamp for the start of this vesting agreement
    uint256 public vestingBegin;

    /// @dev Timestamp for the end of this vesting agreement
    uint256 public vestingEnd;

    /// @dev Timestamp for the last time vested tokens were claimed
    uint256 public lastClaimTimestamp;

    /// @dev Total amount to be vested
    uint256 public immutable vestingAmount;

    /// @dev By how long the vesting should be delayed after activating this contract
    ///      This can be used for multi year vesting agreements
    uint16 public immutable vestingStartDelayInDays;

    /// @dev Inverse finance governance timelock contract
    address public timelock;

    /// @dev Amount of days the vesting period will last
    uint16 public immutable vestingDurationInDays;

    /// @dev Whether this is a reverse vesting agreement
    bool public immutable reverseVesting;

    /// @dev Whether this is vesting agreement can be interrupted
    bool public immutable interruptible;

    /// @dev Inverse finance treasury token
    IInv public immutable inv;

    /**
     * @dev Prevents non timelock from calling a method
     */
    modifier onlyTimelock() {
        require(msg.sender == timelock, "InverseVester:ACCESS_DENIED");
        _;
    }

    constructor(
        address inv_,
        address timelock_,
        uint256 vestingAmount_,
        uint16 vestingDurationInDays_,
        uint16 vestingStartDelayInDays_,
        bool reverseVesting_,
        bool interruptible_,
        address recipient
    ) {
        require(
            inv_ != address(0) && timelock_ != address(0) && recipient != address(0),
            "InverseVester:INVALID_ADDRESS"
        );
        inv = IInv(inv_);
        vestingAmount = vestingAmount_;
        vestingDurationInDays = vestingDurationInDays_;
        reverseVesting = reverseVesting_;
        timelock = timelock_;
        vestingStartDelayInDays = vestingStartDelayInDays_;
        interruptible = interruptible_;
        transferOwnership(recipient);
    }

    /**
     * @notice Activates contract
     */
    function activate() public onlyOwner {
        require(vestingBegin == 0, "InverseVester:ALREADY_ACTIVE");
        inv.safeTransferFrom(timelock, address(this), vestingAmount);
        if (reverseVesting) {
            inv.delegate(owner());
        } else {
            inv.delegate(timelock);
        }
        vestingBegin = lastClaimTimestamp = block.timestamp + (vestingStartDelayInDays * DAY);
        vestingEnd = vestingBegin + (vestingDurationInDays * DAY);
    }

    /**
     * @notice Delegates all votes owned by this contract
     * @dev Only available in reverse vesting
     * @param delegate_ recipient of the votes
     */
    function delegate(address delegate_) public onlyOwner {
        // If this is non reverse vesting, tokens votes stay with treasury
        require(reverseVesting, "InverseVester:DELEGATION_NOT_ALLOWED");
        inv.delegate(delegate_);
    }

    /**
     * @notice Calculates amount of tokens ready to be claimed
     * @return amount Tokens ready to be claimed
     */
    function claimable() public view returns (uint256 amount) {
        if (block.timestamp >= vestingEnd) {
            amount = inv.balanceOf(address(this));
        } else {
            // Claim linearly starting from when claimed lastly
            amount = (vestingAmount * (block.timestamp - lastClaimTimestamp)) / (vestingEnd - vestingBegin);
        }
    }

    /**
     * @notice Calculates amount of tokens still to be vested
     * @return amount Tokens still to be vested
     */
    function unvested() public view returns (uint256 amount) {
        amount = inv.balanceOf(address(this)) - claimable();
    }

    /**
     * @notice Send claimable tokens to contract's owner
     */
    function claim() public {
        require(vestingBegin != 0 && vestingBegin <= block.timestamp, "InverseVester:NOT_STARTED");
        uint256 amount = claimable();
        lastClaimTimestamp = block.timestamp;
        inv.safeTransfer(owner(), amount);
    }

    /**
     * @notice Interrupts this vesting agreement and returns
     *         all unvested tokens to the address provided
     * @param collectionAccount Where to send unvested tokens
     */
    function interrupt(address collectionAccount) external onlyTimelock {
        require(interruptible, "InverseVester:CANNOT_INTERRUPT");
        require(collectionAccount != address(0), "InverseVester:INVALID_ADDRESS");
        inv.safeTransfer(collectionAccount, unvested());
        // if interrupted after activation we terminate vesting now
        if (vestingEnd != 0) {
            vestingEnd = block.timestamp;
        }
    }

    /**
     * @notice Replace timelock
     * @param newTimelock New timelock address
     */
    function setTimelock(address newTimelock) external onlyTimelock {
        require(newTimelock != address(0), "InverseVester:INVALID_ADDRESS");
        timelock = newTimelock;
    }
}
