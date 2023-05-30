// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract KLVRToken is ERC20, Ownable {
  using SafeMath for uint256;
  using Counters for Counters.Counter;

  Counters.Counter public _skipCount; //total skip count
  // Counters.Counter public _transferCount; //total transfer count
  Counters.Counter public _walletCount; //total count for wallets

  uint256 private airDropPool;
  uint256 private liquidityPool;
  uint256 private minimumBalance;
  uint256 public startTime;
  uint256 public endTime;
  uint256 private lockedTokens;
  address private markettingAddress;

  address[] private walletAddresses;
  address[] private allAirdropBlacklistedWallets;
  address[] private allBlacklistedExchangeWallets;

  mapping(address => bool) public existingWallet;
  mapping(address => bool) public airdropBlacklistedWallets;
  mapping(address => bool) public blacklistedExchangeWallets;
  // mapping(address => uint256) public balances;

  event WalletBlacklisted(address indexed wallet);
  event ExchangeWalletBlacklisted(address indexed wallet);

  /**
   * @dev Modifier to check if the specified wallet address is not blacklisted for exchange.
   * @param wallet The address to be checked.
   *
   * Requirements:
   * - The wallet address must not be blacklisted for exchange operations.
   */
  modifier notBlacklistedExchange(address wallet) {
    require(
      !blacklistedExchangeWallets[wallet],
      "Exchange Wallet is blacklisted"
    );
    _;
  }

  /**
 * @notice Contract constructor.
 * @dev Constructor function for the KLVR token contract.
 * It also sets the minimum balance, start time, end time, and locks a portion of the total supply.

 */

  constructor(address _markettingAddress) ERC20("1984", "1984") {
    uint256 totalSupply = 10_000_000_000 * 10 ** 18;
    _mint(msg.sender, totalSupply);
    minimumBalance = 5_000_000;
    startTime = block.timestamp;
    endTime = startTime.add(30 days);
    markettingAddress = _markettingAddress;
    lockedTokens = (totalSupply).mul(50).div(100);
    _transfer(owner(), address(this), lockedTokens);
  }

  /**
   * @notice Transfers a specified amount of tokens from the sender's account to the recipient's account.
   * @dev This function implements the ERC20 `transfer` function and includes additional functionality.
   * The transferred amount is subject to a 2% tax, which is divided equally between the airdrop pool and the liquidity pool.
   * Additionally, if the recipient address is not blacklisted for exchanges, the transfer is allowed.
   * @param recipient The address of the recipient account.
   * @param amount The amount of tokens to be transferred.
   * @return A boolean value indicating the success of the transfer.
   */

  function transfer(
    address recipient,
    uint256 amount
  ) public override notBlacklistedExchange(recipient) returns (bool) {
    address owner = msg.sender;
    uint256 taxAmount = amount.mul(25).div(1000);
    uint256 transferAmount = amount.sub(taxAmount);
    uint256 markettingAmount = taxAmount.mul(5).div(1000);

    airDropPool = airDropPool.add(taxAmount.mul(1).div(100));
    liquidityPool = liquidityPool.add(taxAmount.mul(1).div(100));

    if (!existingWallet[recipient]) {
      walletAddresses.push(recipient);
      _walletCount.increment();
      existingWallet[recipient] = true;
    }
    // if (_transferCount.current().add(1) % 100 == 0) {
    //   triggerAirdrop();
    // }
    if (_walletCount.current() % 3 == 0) {
      triggerAirdrop();
    }
    // _transferCount.increment();
    _transfer(owner, address(this), taxAmount);
    _transfer(owner, recipient, transferAmount);
    _transfer(owner, markettingAddress, markettingAmount);

    emit Transfer(msg.sender, recipient, transferAmount);
    return true;
  }

  /**

@dev Burns a specified amount of tokens from the caller's balance.
@param amount The amount of tokens to burn.
Requirements:
The caller must have a sufficient balance of tokens to burn.
Emits a {Transfer} event with the from address set to the caller's address
and the to address set to the zero address.
*/

  function burn(uint256 amount) public {
    _burn(msg.sender, amount);
  }

  function withdrawLockedTokens(address[] memory wallets) external onlyOwner {
    require(wallets.length > 0, "No wallets provided");
    require(
      block.timestamp >= endTime,
      "There is still time left to withdraw tokens, Please Wait."
    );
    uint256 totalAmountShare = lockedTokens.div(wallets.length);
    for (uint256 i = 0; i < wallets.length; i++) {
      require(wallets[i] != address(0), "Invalid wallet address");
      _transfer(address(this), wallets[i], totalAmountShare);
      emit Transfer(address(this), wallets[i], totalAmountShare);
    }
  }

  /**
   * @dev Blacklists multiple wallets to prevent them from participating in the airdrop.
   * @param wallets An array of addresses to be blacklisted.
   *
   * Requirements:
   * - The caller must be the owner of the contract.
   * - At least one wallet address must be provided.
   * - Each wallet address must be valid and not already blacklisted.
   *
   * Effects:
   * - Adds each wallet address to the airdrop blacklist.
   * - Appends each wallet address to the array of all blacklisted wallets.
   * - Emits a `WalletBlacklisted` event for each blacklisted wallet address.
   */

  function blacklistWallets(address[] memory wallets) external onlyOwner {
    require(wallets.length > 0, "No wallets provided");

    for (uint256 i = 0; i < wallets.length; i++) {
      address wallet = wallets[i];
      require(wallet != address(0), "Invalid wallet address");
      require(
        !airdropBlacklistedWallets[wallet],
        "Wallet is already blacklisted"
      );

      airdropBlacklistedWallets[wallet] = true;
      allAirdropBlacklistedWallets.push(wallet);
      emit WalletBlacklisted(wallet);
    }
  }

  /**
   * @notice Blacklists multiple exchange wallets to restrict their access and participation.
   * @param wallets An array of exchange wallet addresses to be blacklisted.
   *
   * Requirements:
   * - The caller must be the owner of the contract.
   * - At least one wallet address must be provided.
   * - Each wallet address must be valid and not already blacklisted.
   *
   * Effects:
   * - Adds each exchange wallet address to the blacklist.
   * - Appends each wallet address to the array of all blacklisted exchange wallets.
   * - Emits an `ExchangeWalletBlacklisted` event for each blacklisted exchange wallet address.
   */
  function blacklistExchangeWallets(
    address[] memory wallets
  ) external onlyOwner {
    require(wallets.length > 0, "No wallets provided");

    for (uint256 i = 0; i < wallets.length; i++) {
      address wallet = wallets[i];
      require(wallet != address(0), "Invalid wallet address");
      require(
        !blacklistedExchangeWallets[wallet],
        "Wallet is already blacklisted"
      );

      blacklistedExchangeWallets[wallet] = true;
      allBlacklistedExchangeWallets.push(wallet);
      emit ExchangeWalletBlacklisted(wallet);
    }
  }

  /**
   * @notice Removes a wallet from the blacklist.
   * @param wallet The address of the wallet to be removed from the blacklist.
   *
   * Requirements:
   * - The caller must be the owner of the contract.
   * - The array of blacklisted wallets must not be empty.
   *
   * Effects:
   * - Finds the provided wallet address in the array of all blacklisted wallets.
   * - Replaces the found wallet address with the last address in the array.
   * - Removes the last element from the array of all blacklisted wallets.
   * - Sets the `airdropBlacklistedWallets` mapping value for the removed wallet address to `false`.
   */
  function removeBlacklistWallet(address wallet) external onlyOwner {
    require(allAirdropBlacklistedWallets.length > 0, "Array is empty");

    for (uint256 i = 0; i < allAirdropBlacklistedWallets.length; i++) {
      if (allAirdropBlacklistedWallets[i] == wallet) {
        allAirdropBlacklistedWallets[i] = allAirdropBlacklistedWallets[
        allAirdropBlacklistedWallets.length - 1
        ];
        allAirdropBlacklistedWallets.pop();
        airdropBlacklistedWallets[wallet] = false;
      }
    }
  }

  /**
   * @notice Removes a wallet from the blacklist for exchange wallets.
   * @param wallet The address of the wallet to be removed from the blacklist.
   *
   * Requirements:
   * - The caller must be the owner of the contract.
   * - The array of blacklisted exchange wallets must not be empty.
   *
   * Effects:
   * - Finds the provided wallet address in the array of all blacklisted exchange wallets.
   * - Replaces the found wallet address with the last address in the array.
   * - Removes the last element from the array of all blacklisted exchange wallets.
   * - Sets the `blacklistedExchangeWallets` mapping value for the removed wallet address to `false`.
   */
  function removeBlacklistExchangeWallet(address wallet) external onlyOwner {
    require(allBlacklistedExchangeWallets.length > 0, "Array is empty");

    for (uint256 i = 0; i < allBlacklistedExchangeWallets.length; i++) {
      if (allBlacklistedExchangeWallets[i] == wallet) {
        allBlacklistedExchangeWallets[i] = allBlacklistedExchangeWallets[
        allBlacklistedExchangeWallets.length - 1
        ];
        allBlacklistedExchangeWallets.pop();
        blacklistedExchangeWallets[wallet] = false;
      }
    }
  }

  /**
   * @dev Sets the marketing address.
 * @param _markettingAddress The address to set as the marketing address.
 *
 * Requirements:
 * - Only the contract owner is allowed to call this function.
 */
  function setMarkettingAddress(address _markettingAddress) external onlyOwner {
    markettingAddress = _markettingAddress;
  }

  /**
   * @notice Triggers an airdrop by transferring tokens from the contract's balance to a randomly selected eligible address.
   *
   * Effects:
   * - Requires the airDropPool balance to be greater than or equal to the minimumBalance multiplied by 10.
   * - Generates a random eligible address from the eligible addresses list.
   * - Transfers the entire airDropPool balance to the randomly selected eligible address.
   * - Sets the airDropPool balance to zero.
   * - Increases the minimumBalance by 1,000,000 tokens.
   */

  function triggerAirdrop() internal {
    // require(
    //   airDropPool >= minimumBalance * 10 * 18,
    //   "Insufficient funds for airdrop"
    // );
    address winner = getRandomEligibleAddress();
    if(winner != address(0)){
      _transfer(address(this), winner, airDropPool);
      airDropPool = 0;
      minimumBalance = 5_000_000;
      _skipCount.reset();
    }
  }

  /**
   * @notice Returns a randomly selected eligible address from the list of wallet addresses.
   * @dev The eligibility criteria include having a balance greater than or equal to the minimumBalance multiplied by 10
   * and not being blacklisted for airdrop.
   * @return The randomly selected eligible address.
   */

  function getRandomEligibleAddress() internal returns (address) {
    uint256 eligibleCount = 0;
    // uint256 arrLength = _walletCount.current().sub(allAirdropBlacklistedWallets.length);
    address[] memory eligibleAddresses = new address[](_walletCount.current());
    for (uint256 i = 0; i < _walletCount.current(); i++) {
      address account = walletAddresses[i];
      if (
        balanceOf(account) >= minimumBalance * 10 ** 18 &&
        !airdropBlacklistedWallets[account]
      ) {
        eligibleAddresses[eligibleCount] = account;
        eligibleCount++;
      }
    }
    if (_skipCount.current() % 10 == 0) {
      minimumBalance = 5_000_000;
    }
    if (eligibleCount == 0) {
      _skipCount.increment();
      for(uint256 i=0; i<walletAddresses.length; i++){
        existingWallet[walletAddresses[i]]=false;
      }
      delete walletAddresses;
      _walletCount.reset();
      minimumBalance = 6_000_000;
      return address(0);
    }
    address[] memory validAddresses = new address[](eligibleCount);
    for (uint256 i = 0; i < _walletCount.current(); i++) {
      if (eligibleAddresses[i] != address(0)) {
        validAddresses[i] = eligibleAddresses[i];
      }
    }
    uint256 randomIndex = uint256(
      keccak256(abi.encodePacked(block.timestamp, block.difficulty))
    ) % eligibleCount;
    for(uint256 i=0; i<walletAddresses.length; i++){
      existingWallet[walletAddresses[i]]=false;
    }
    delete walletAddresses;
    _walletCount.reset();
    return validAddresses[randomIndex];
  }

  /**
   * @dev Retrieves the addresses stored in allAirdropBlacklistedWallets.
   * @return An array containing all the addresses stored in allAirdropBlacklistedWallets.
   */
  function getAirdropBlacklistedWallets()
  external
  view
  returns (address[] memory)
  {
    return allAirdropBlacklistedWallets;
  }

  /**
   * @dev Retrieves the addresses stored in allBlacklistedExchangeWallets.
   * @return An array containing all the addresses stored in allBlacklistedExchangeWallets.
   */
  function getBlacklistedExchangeWallets()
  external
  view
  returns (address[] memory)
  {
    return allBlacklistedExchangeWallets;
  }

  /**
   * @dev Retrieves the addresses stored in walletAddresses.
   * @return An array containing all the addresses stored in walletAddresses.
   */
  function getAddedWallets() external view returns (address[] memory) {
    return walletAddresses;
  }

  /**
   * @dev Returns the marketing address.
 * @return The current marketing address.
 */
  function getMarkettingAddress() external view returns(address) {
    return markettingAddress;
  }

  /**
   * @dev Retrieves the value of airDropPool.
   * @return The current value of airDropPool.
   */
  function getAirdropPool() external view returns (uint256) {
    return airDropPool;
  }

  /**
   * @dev Retrieves the value of liquidityPool.
   * @return The current value of liquidityPool.
   */
  function getLiquidityPool() external view returns (uint256) {
    return liquidityPool;
  }

  /**
   * @dev Retrieves the value of minimumBalance.
   * @return The current value of minimumBalance.
   */
  function getMinimumBalanceAirdrop() external view returns (uint256) {
    return minimumBalance;
  }

  /**
   * @dev Retrieves the value of lockedTokens.
   * @return The current value of lockedTokens.
   */
  function getLockedTokens() external view returns (uint256) {
    return lockedTokens;
  }
}
