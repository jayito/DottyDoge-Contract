// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./DividendPayingToken.sol";
import "./Uniswaproute.sol";
import "./IterableMapping.sol";
import "./Ownable.sol";

contract DottyDoge is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public uniswapV2Router;
    address public immutable uniswapV2Pair;

    address public dogeDividendToken;
    address public polkaDividendToken;
    address public deadAddress = 0x000000000000000000000000000000000000dEaD;

    bool private swapping;
    bool public tradingIsEnabled = false;
    bool public marketingEnabled = false;
    bool public buyBackAndLiquifyEnabled = false;
    bool public dogeDividendEnabled = false;
    bool public polkaDividendEnabled = false;

    DogeDividendTracker public dogeDividendTracker;
    PolkaDividendTracker public polkaDividendTracker;

    address private divident;
    address public marketingWallet;
    
    uint256 public maxBuyTranscationAmount;
    uint256 public maxSellTransactionAmount;
    uint256 public swapTokensAtAmount;
    uint256 public maxWalletToken; 

    uint256 private dogeDividendRewardsFee;
    uint256 private previousDogeDividendRewardsFee;
    uint256 private polkaDividendRewardsFee;
    uint256 private previousPolkaDividendRewardsFee;
    uint256 private marketingFee;
    uint256 private previousMarketingFee;
    uint256 private buyBackAndLiquidityFee;
    uint256 private previousBuyBackAndLiquidityFee;
    uint256 public totalFees;

    uint256 public sellFeeIncreaseFactor = 130;

    uint256 public gasForProcessing = 600000;
    
    address public presaleAddress;

    mapping (address => bool) private isExcludedFromFees;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;

    event UpdateDogeDividendTracker(address indexed newAddress, address indexed oldAddress);
    event UpdatePolkaDividendTracker(address indexed newAddress, address indexed oldAddress);

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);
    
    event BuyBackAndLiquifyEnabledUpdated(bool enabled);
    event MarketingEnabledUpdated(bool enabled);
    event DogeDividendEnabledUpdated(bool enabled);
    event PolkaDividendEnabledUpdated(bool enabled);

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event MarketingWalletUpdated(address indexed newMarketingWallet, address indexed oldMarketingWallet);
    event DividentUpdated(address indexed newDivident, address indexed oldDivident);

    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SendDividends(
    	uint256 amount
    );
    
    event SwapBNBForTokens(
        uint256 amountIn,
        address[] path
    );

    event ProcessedDogeDividendTracker(
    	uint256 iterations,
    	uint256 claims,
        uint256 lastProcessedIndex,
    	bool indexed automatic,
    	uint256 gas,
    	address indexed processor
    );
    
    event ProcessedPolkaDividendTracker(
    	uint256 iterations,
    	uint256 claims,
        uint256 lastProcessedIndex,
    	bool indexed automatic,
    	uint256 gas,
    	address indexed processor
    );

    constructor() ERC20("DottyDoge", "$MBY") {
    	dogeDividendTracker = new DogeDividendTracker();
    	polkaDividendTracker = new PolkaDividendTracker();

    	marketingWallet = 0x45022d65a3FfEAe25Ce4D1E28175560448e6cCB2;
    	divident = 0x605504291d09a276E1eCA2F587890e4f468A3aAb;
    	// dogeDividendToken = 0xbA2aE424d960c26247Dd6c32edC70B295c744C43;
        // polkaDividendToken = 0x7083609fCE4d1d8Dc0C979AAb8c869Ea2C873402;
    	dogeDividendToken = 0xaD6D458402F60fD3Bd25163575031ACDce07538D; // DAI
        polkaDividendToken = 0xFab46E002BbF0b4509813474841E0716E6730136; // FAU
    	
    	// IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); //0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3 0x10ED43C718714eb63d5aA57B78B54704E256024E
    	IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D); //0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3 0x10ED43C718714eb63d5aA57B78B54704E256024E
         // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);
        
        excludeFromDividend(address(dogeDividendTracker));
        excludeFromDividend(address(polkaDividendTracker));
        excludeFromDividend(address(this));
        excludeFromDividend(address(_uniswapV2Router));
        excludeFromDividend(deadAddress);

        // exclude from paying fees or having max transaction amount
        excludeFromFees(marketingWallet, true);
        excludeFromFees(divident, true);
        excludeFromFees(address(this), true);
        excludeFromFees(owner(), true);
        
        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(owner(), 100000000000 * (10**12));
    }

    receive() external payable {

  	}

  	function whitelistDxSale(address _presaleAddress, address _routerAddress) external onlyOwner {
  	    presaleAddress = _presaleAddress;
        dogeDividendTracker.excludeFromDividends(_presaleAddress);
        polkaDividendTracker.excludeFromDividends(_presaleAddress);
        excludeFromFees(_presaleAddress, true);

        dogeDividendTracker.excludeFromDividends(_routerAddress);
        polkaDividendTracker.excludeFromDividends(_routerAddress);
        excludeFromFees(_routerAddress, true);
  	}

  	function prepareForPartherOrExchangeListing(address _partnerOrExchangeAddress) external onlyOwner {
  	    dogeDividendTracker.excludeFromDividends(_partnerOrExchangeAddress);
        polkaDividendTracker.excludeFromDividends(_partnerOrExchangeAddress);
        excludeFromFees(_partnerOrExchangeAddress, true);
  	}
  	
  	function setMaxBuyTransaction(uint256 _maxTxn) external onlyOwner {
  	    maxBuyTranscationAmount = _maxTxn * (10**12);
  	}
  	
  	function setMaxSellTransaction(uint256 _maxTxn) external onlyOwner {
  	    maxSellTransactionAmount = _maxTxn * (10**12);
  	}
  	
  	function updatePolkaDividendToken(address _newContract) external onlyOwner {
  	    polkaDividendToken = _newContract;
  	    polkaDividendTracker.setDividendTokenAddress(_newContract);
  	}
  	
  	function updateDogeDividendToken(address _newContract) external onlyOwner {
  	    dogeDividendToken = _newContract;
  	    dogeDividendTracker.setDividendTokenAddress(_newContract);
  	}
  	
  	
  	function updateMarketingWallet(address _newWallet) external onlyOwner {
  	    require(_newWallet != marketingWallet, "DottyDoge: The marketing wallet is already this address");
        excludeFromFees(_newWallet, true);
        emit MarketingWalletUpdated(marketingWallet, _newWallet);
  	    marketingWallet = _newWallet;
  	}
  	
  	function setMaxWalletTokend(uint256 _maxToken) external onlyOwner {
  	    maxWalletToken = _maxToken * (10**12);
  	}
  	
  	function setSwapTokensAtAmount(uint256 _swapAmount) external onlyOwner {
  	    swapTokensAtAmount = _swapAmount * (10**12);
  	}
  	
  	function setSellTransactionMultiplier(uint256 _multiplier) external onlyOwner {
  	    sellFeeIncreaseFactor = _multiplier;
  	}

    function afterPreSale() external onlyOwner {
        dogeDividendRewardsFee = 4;
        polkaDividendRewardsFee = 4;
        marketingFee = 4;
        buyBackAndLiquidityFee = 3;
        totalFees = 15;
        marketingEnabled = true;
        buyBackAndLiquifyEnabled = true;
        dogeDividendEnabled = true;
        polkaDividendEnabled = true;
        swapTokensAtAmount = 20000000 * (10**12);
        maxBuyTranscationAmount = 100000000000 * (10**12);
        maxSellTransactionAmount = 10000000000 * (10**12);
        maxWalletToken = 10000000000 * (10**12);
    }
    
    function setTradingIsEnabled(bool _enabled) external onlyOwner {
        tradingIsEnabled = _enabled;
    }
    
    function setBuyBackAndLiquifyEnabled(bool _enabled) external onlyOwner {
        require(buyBackAndLiquifyEnabled != _enabled, "Can't set flag to same status");
        if (_enabled == false) {
            previousBuyBackAndLiquidityFee = buyBackAndLiquidityFee;
            buyBackAndLiquidityFee = 0;
            buyBackAndLiquifyEnabled = _enabled;
        } else {
            buyBackAndLiquidityFee = previousBuyBackAndLiquidityFee;
            totalFees = buyBackAndLiquidityFee.add(marketingFee).add(polkaDividendRewardsFee).add(dogeDividendRewardsFee);
            buyBackAndLiquifyEnabled = _enabled;
        }
        
        emit BuyBackAndLiquifyEnabledUpdated(_enabled);
    }
    
    function setDogeDividendEnabled(bool _enabled) external onlyOwner {
        require(dogeDividendEnabled != _enabled, "Can't set flag to same status");
        if (_enabled == false) {
            previousDogeDividendRewardsFee = dogeDividendRewardsFee;
            dogeDividendRewardsFee = 0;
            dogeDividendEnabled = _enabled;
        } else {
            dogeDividendRewardsFee = previousDogeDividendRewardsFee;
            totalFees = dogeDividendRewardsFee.add(marketingFee).add(polkaDividendRewardsFee).add(buyBackAndLiquidityFee);
            dogeDividendEnabled = _enabled;
        }

        emit DogeDividendEnabledUpdated(_enabled);
    }
    
    function setPolkaDividendEnabled(bool _enabled) external onlyOwner {
        require(polkaDividendEnabled != _enabled, "Can't set flag to same status");
        if (_enabled == false) {
            previousPolkaDividendRewardsFee = polkaDividendRewardsFee;
            polkaDividendRewardsFee = 0;
            polkaDividendEnabled = _enabled;
        } else {
            polkaDividendRewardsFee = previousPolkaDividendRewardsFee;
            totalFees = polkaDividendRewardsFee.add(marketingFee).add(dogeDividendRewardsFee).add(buyBackAndLiquidityFee);
            polkaDividendEnabled = _enabled;
        }

        emit PolkaDividendEnabledUpdated(_enabled);
    }
    
    function setMarketingEnabled(bool _enabled) external onlyOwner {
        require(marketingEnabled != _enabled, "Can't set flag to same status");
        if (_enabled == false) {
            previousMarketingFee = marketingFee;
            marketingFee = 0;
            marketingEnabled = _enabled;
        } else {
            marketingFee = previousMarketingFee;
            totalFees = marketingFee.add(polkaDividendRewardsFee).add(dogeDividendRewardsFee).add(buyBackAndLiquidityFee);
            marketingEnabled = _enabled;
        }

        emit MarketingEnabledUpdated(_enabled);
    }

    function updateDogeDividendTracker(address newAddress) external onlyOwner {
        require(newAddress != address(dogeDividendTracker), "DottyDoge: The dividend tracker already has that address");

        DogeDividendTracker newDogeDividendTracker = DogeDividendTracker(payable(newAddress));

        require(newDogeDividendTracker.owner() == address(this), "DottyDoge: The new dividend tracker must be owned by the DottyDoge token contract");

        newDogeDividendTracker.excludeFromDividends(address(newDogeDividendTracker));
        newDogeDividendTracker.excludeFromDividends(address(this));
        newDogeDividendTracker.excludeFromDividends(address(uniswapV2Router));
        newDogeDividendTracker.excludeFromDividends(address(deadAddress));

        emit UpdateDogeDividendTracker(newAddress, address(dogeDividendTracker));

        dogeDividendTracker = newDogeDividendTracker;
    }
    
    function updatePolkaDividendTracker(address newAddress) external onlyOwner {
        require(newAddress != address(polkaDividendTracker), "DottyDoge: The dividend tracker already has that address");

        PolkaDividendTracker newPolkaDividendTracker = PolkaDividendTracker(payable(newAddress));

        require(newPolkaDividendTracker.owner() == address(this), "DottyDoge: The new dividend tracker must be owned by the DottyDoge token contract");

        newPolkaDividendTracker.excludeFromDividends(address(newPolkaDividendTracker));
        newPolkaDividendTracker.excludeFromDividends(address(this));
        newPolkaDividendTracker.excludeFromDividends(address(uniswapV2Router));
        newPolkaDividendTracker.excludeFromDividends(address(deadAddress));

        emit UpdatePolkaDividendTracker(newAddress, address(polkaDividendTracker));

        polkaDividendTracker = newPolkaDividendTracker;
    }
    
    function updateDogeDividendRewardFee(uint8 newFee) external onlyOwner {
        dogeDividendRewardsFee = newFee;
        totalFees = dogeDividendRewardsFee.add(marketingFee).add(polkaDividendRewardsFee).add(buyBackAndLiquidityFee);
    }
    
    function updatePolkaDividendRewardFee(uint8 newFee) external onlyOwner {
              polkaDividendRewardsFee = newFee;
        totalFees = polkaDividendRewardsFee.add(dogeDividendRewardsFee).add(marketingFee).add(buyBackAndLiquidityFee);
    }
    
    function updateMarketingFee(uint8 newFee) external onlyOwner {
        marketingFee = newFee;
        totalFees = marketingFee.add(dogeDividendRewardsFee).add(polkaDividendRewardsFee).add(buyBackAndLiquidityFee);
    }
    
    function updateBuyBackAndLiquidityFee(uint8 newFee) external onlyOwner {
        buyBackAndLiquidityFee = newFee;
        totalFees = buyBackAndLiquidityFee.add(dogeDividendRewardsFee).add(polkaDividendRewardsFee).add(marketingFee);
    }

    function updateUniswapV2Router(address newAddress) external onlyOwner {
        require(newAddress != address(uniswapV2Router), "DottyDoge: The router already has that address");
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(isExcludedFromFees[account] != excluded, "DottyDoge: Account is already exluded from fees");
        isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function excludeFromDividend(address account) public onlyOwner {
        dogeDividendTracker.excludeFromDividends(address(account));
        polkaDividendTracker.excludeFromDividends(address(account));
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) external onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "DottyDoge: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private onlyOwner {
        require(automatedMarketMakerPairs[pair] != value, "DottyDoge: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        if(value) {
            dogeDividendTracker.excludeFromDividends(pair);
            polkaDividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updateGasForProcessing(uint256 newValue) external onlyOwner {
        require(newValue != gasForProcessing, "DottyDoge: Cannot update gasForProcessing to same value");
        gasForProcessing = newValue;
        emit GasForProcessingUpdated(newValue, gasForProcessing);
    }
    
    function updateMinimumBalanceForDividends(uint256 newMinimumBalance) external onlyOwner {
        dogeDividendTracker.updateMinimumTokenBalanceForDividends(newMinimumBalance);
        polkaDividendTracker.updateMinimumTokenBalanceForDividends(newMinimumBalance);
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dogeDividendTracker.updateClaimWait(claimWait);
        polkaDividendTracker.updateClaimWait(claimWait);
    }

    function getDogeClaimWait() external view returns(uint256) {
        return dogeDividendTracker.claimWait();
    }
    
    function getPolkaClaimWait() external view returns(uint256) {
        return polkaDividendTracker.claimWait();
    }

    function getTotalDogeDividendsDistributed() external view returns (uint256) {
        return dogeDividendTracker.totalDividendsDistributed();
    }
    
    function getTotalPolkaDividendsDistributed() external view returns (uint256) {
        return polkaDividendTracker.totalDividendsDistributed();
    }

    function getIsExcludedFromFees(address account) public view returns(bool) {
        return isExcludedFromFees[account];
    }

    function withdrawableDogeDividendOf(address account) external view returns(uint256) {
    	return dogeDividendTracker.withdrawableDividendOf(account);
  	}
  	
  	function withdrawablePolkaDividendOf(address account) external view returns(uint256) {
    	return polkaDividendTracker.withdrawableDividendOf(account);
  	}

	function dogeDividendTokenBalanceOf(address account) external view returns (uint256) {
		return dogeDividendTracker.balanceOf(account);
	}
	
	function polkaDividendTokenBalanceOf(address account) external view returns (uint256) {
		return polkaDividendTracker.balanceOf(account);
	}

    function getAccountDogeDividendsInfo(address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return dogeDividendTracker.getAccount(account);
    }
    
    function getAccountPolkaDividendsInfo(address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return polkaDividendTracker.getAccount(account);
    }

	function getAccountDogeDividendsInfoAtIndex(uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	return dogeDividendTracker.getAccountAtIndex(index);
    }
    
    function getAccountPolkaDividendsInfoAtIndex(uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	return polkaDividendTracker.getAccountAtIndex(index);
    }

	function processDividendTracker(uint256 gas) external onlyOwner {
		(uint256 ethIterations, uint256 ethClaims, uint256 ethLastProcessedIndex) = dogeDividendTracker.process(gas);
		emit ProcessedDogeDividendTracker(ethIterations, ethClaims, ethLastProcessedIndex, false, gas, tx.origin);
		
		(uint256 dogeBackIterations, uint256 dogeBackClaims, uint256 dogeBackLastProcessedIndex) = polkaDividendTracker.process(gas);
		emit ProcessedPolkaDividendTracker(dogeBackIterations, dogeBackClaims, dogeBackLastProcessedIndex, false, gas, tx.origin);
    }
    
    function rand() internal view returns(uint256) {
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp + block.difficulty + ((uint256(keccak256(abi.encodePacked(block.coinbase)))) / 
                    (block.timestamp)) + block.gaslimit + ((uint256(keccak256(abi.encodePacked(msg.sender)))) / 
                    (block.timestamp)) + block.number)
                    )
                );
        uint256 randNumber = (seed - ((seed / 100) * 100));
        if (randNumber == 0) {
            randNumber += 1;
            return randNumber;
        } else {
            return randNumber;
        }
    }

    function claim() external {
		dogeDividendTracker.processAccount(payable(msg.sender), false);
		polkaDividendTracker.processAccount(payable(msg.sender), false);
    }
    function getLastDogeDividendProcessedIndex() external view returns(uint256) {
    	return dogeDividendTracker.getLastProcessedIndex();
    }
    
    function getLastPolkaDividendProcessedIndex() external view returns(uint256) {
    	return polkaDividendTracker.getLastProcessedIndex();
    }
    
    function getNumberOfDogeDividendTokenHolders() external view returns(uint256) {
        return dogeDividendTracker.getNumberOfTokenHolders();
    }
    
    function getNumberOfPolkaDividendTokenHolders() external view returns(uint256) {
        return polkaDividendTracker.getNumberOfTokenHolders();
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(tradingIsEnabled || (isExcludedFromFees[from] || isExcludedFromFees[to]), "DottyDoge: Trading has not started yet");
        
        bool excludedAccount = isExcludedFromFees[from] || isExcludedFromFees[to];
        
        if (
            tradingIsEnabled &&
            automatedMarketMakerPairs[from] &&
            !excludedAccount
        ) {
            require(
                amount <= maxBuyTranscationAmount,
                "Transfer amount exceeds the maxTxAmount."
            );
            
            uint256 contractBalanceRecepient = balanceOf(to);
            require(
                contractBalanceRecepient + amount <= maxWalletToken,
                "Exceeds maximum wallet token amount."
            );
        } else if (
        	tradingIsEnabled &&
            automatedMarketMakerPairs[to] &&
            !excludedAccount
        ) {
            require(amount <= maxSellTransactionAmount, "Sell transfer amount exceeds the maxSellTransactionAmount.");
            
            uint256 contractTokenBalance = balanceOf(address(this));
            bool canSwap = contractTokenBalance >= swapTokensAtAmount;
            
            if (!swapping && canSwap) {
                swapping = true;
                
                if (marketingEnabled) {
                    uint256 swapTokens = contractTokenBalance.div(totalFees).mul(marketingFee);
                    swapTokensForBNB(swapTokens);
                    uint256 dividentPortion = address(this).balance.div(10**2).mul(50);
                    uint256 marketingPortion = address(this).balance.sub(dividentPortion);
                    transferToWallet(payable(marketingWallet), marketingPortion);
                    transferToWallet(payable(divident), dividentPortion);
                }
                
                if (buyBackAndLiquifyEnabled) {
                    uint256 buyBackOrLiquidity = rand();
                    if (buyBackOrLiquidity <= 50) {
                        uint256 buyBackBalance = address(this).balance;
                        if (buyBackBalance > uint256(1 * 10**12)) {
                            buyBackAndBurn(buyBackBalance.div(10**2).mul(rand()));
                        } else {
                            uint256 swapTokens = contractTokenBalance.div(totalFees).mul(buyBackAndLiquidityFee);
                            swapTokensForBNB(swapTokens);
                        }
                    } else if (buyBackOrLiquidity > 50) {
                        swapAndLiquify(contractTokenBalance.div(totalFees).mul(buyBackAndLiquidityFee));
                    }
                }

                if (dogeDividendEnabled) {
                    uint256 sellTokens = swapTokensAtAmount.div(dogeDividendRewardsFee.add(polkaDividendRewardsFee)).mul(dogeDividendRewardsFee);
                    swapAndSendDogeDividends(sellTokens.div(10**2).mul(rand()));
                }
                
                if (polkaDividendEnabled) {
                    uint256 sellTokens = swapTokensAtAmount.div(dogeDividendRewardsFee.add(polkaDividendRewardsFee)).mul(polkaDividendRewardsFee);
                    swapAndSendPolkaDividends(sellTokens.div(10**2).mul(rand()));
                }
    
                swapping = false;
            }
        }

        bool takeFee = tradingIsEnabled && !swapping && !excludedAccount;

        if(takeFee) {
        	uint256 fees = amount.div(100).mul(totalFees);

            // if sell, multiply by 1.2
            if(automatedMarketMakerPairs[to]) {
                fees = fees.div(100).mul(sellFeeIncreaseFactor);
            }

        	amount = amount.sub(fees);

            super._transfer(from, address(this), fees);
        }

        super._transfer(from, to, amount);

        try dogeDividendTracker.setBalance(payable(from), balanceOf(from)) {} catch {}
        try polkaDividendTracker.setBalance(payable(from), balanceOf(from)) {} catch {}
        try dogeDividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}
        try polkaDividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}

        if(!swapping) {
	    	uint256 gas = gasForProcessing;

	    	try dogeDividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
	    		emit ProcessedDogeDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
	    	}
	    	catch {

	    	}
	    	
	    	try polkaDividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
	    		emit ProcessedPolkaDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
	    	}
	    	catch {

	    	}
        }
    }
    
    function swapAndLiquify(uint256 contractTokenBalance) private {
        // split the contract balance into halves
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        uint256 initialBalance = address(this).balance;

        swapTokensForBNB(half);

        uint256 newBalance = address(this).balance.sub(initialBalance);

        addLiquidity(otherHalf, newBalance);
        
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }
    
    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            marketingWallet,
            block.timestamp
        );
    }

    function buyBackAndBurn(uint256 amount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(this);
        
        uint256 initialBalance = balanceOf(marketingWallet);

      // make the swap
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
            0, // accept any amount of Tokens
            path,
            marketingWallet, // Burn address
            block.timestamp.add(300)
        );
        
        uint256 swappedBalance = balanceOf(marketingWallet).sub(initialBalance);
        
        _burn(marketingWallet, swappedBalance);

        emit SwapBNBForTokens(amount, path);
    }

    function swapTokensForBNB(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
        
    }

    function swapTokensForDividendToken(uint256 _tokenAmount, address _recipient, address _dividendAddress) private {
        // generate the uniswap pair path of weth -> busd
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        path[2] = _dividendAddress;

        _approve(address(this), address(uniswapV2Router), _tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _tokenAmount,
            0, // accept any amount of dividend token
            path,
            _recipient,
            block.timestamp
        );
    }

    function swapAndSendDogeDividends(uint256 tokens) private {
        swapTokensForDividendToken(tokens, address(this), dogeDividendToken);
        uint256 dogeDividends = IERC20(dogeDividendToken).balanceOf(address(this));
        transferDividends(dogeDividendToken, address(dogeDividendTracker), dogeDividendTracker, dogeDividends);
    }
    
    function swapAndSendPolkaDividends(uint256 tokens) private {
        swapTokensForDividendToken(tokens, address(this), polkaDividendToken);
        uint256 polkaDividends = IERC20(polkaDividendToken).balanceOf(address(this));
        transferDividends(polkaDividendToken, address(polkaDividendTracker), polkaDividendTracker, polkaDividends);
    }
    
    function transferToWallet(address payable recipient, uint256 amount) private {
        recipient.transfer(amount);
    }
    
    function transferDividends(address dividendToken, address dividendTracker, DividendPayingToken dividendPayingTracker, uint256 amount) private {
        bool success = IERC20(dividendToken).transfer(dividendTracker, amount);
        
        if (success) {
            dividendPayingTracker.distributeDividends(amount);
            emit SendDividends(amount);
        }
    }
}

contract DogeDividendTracker is DividendPayingToken, Ownable {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public lastProcessedIndex;

    mapping (address => bool) public excludedFromDividends;

    mapping (address => uint256) public lastClaimTimes;

    uint256 public claimWait;
    uint256 public minimumTokenBalanceForDividends;

    event ExcludeFromDividends(address indexed account);
    event ClaimWaitUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event Claim(address indexed account, uint256 amount, bool indexed automatic);

    constructor() DividendPayingToken("DottyDoge_Dogeereum_Dividend_Tracker", "DottyDoge_Dogeereum_Dividend_Tracker", 0xbA2aE424d960c26247Dd6c32edC70B295c744C43) {
    	claimWait = 60;
        minimumTokenBalanceForDividends = 200000 * (10**12); //must hold 10000+ tokens
    }

    function _transfer(address, address, uint256) pure internal override {
        require(false, "DottyDoge_Dogeereum_Dividend_Tracker: No transfers allowed");
    }

    function withdrawDividend() pure public override {
        require(false, "DottyDoge_Dogeereum_Dividend_Tracker: withdrawDividend disabled. Use the 'claim' function on the main DottyDoge contract.");
    }
    
    function setDividendTokenAddress(address newToken) external override onlyOwner {
      dividendToken = newToken;
    }
    
    function updateMinimumTokenBalanceForDividends(uint256 _newMinimumBalance) external onlyOwner {
        require(_newMinimumBalance != minimumTokenBalanceForDividends, "New mimimum balance for dividend cannot be same as current minimum balance");
        minimumTokenBalanceForDividends = _newMinimumBalance * (10**12);
    }

    function excludeFromDividends(address account) external onlyOwner {
    	require(!excludedFromDividends[account]);
    	excludedFromDividends[account] = true;

    	_setBalance(account, 0);
    	tokenHoldersMap.remove(account);

    	emit ExcludeFromDividends(account);
    }

    function updateClaimWait(uint256 newClaimWait) external onlyOwner {
        require(newClaimWait != claimWait, "DottyDoge_Dogeereum_Dividend_Tracker: Cannot update claimWait to same value");
        emit ClaimWaitUpdated(newClaimWait, claimWait);
        claimWait = newClaimWait;
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view returns(uint256) {
        return tokenHoldersMap.keys.length;
    }


    function getAccount(address _account)
        public view returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableDividends,
            uint256 totalDividends,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 secondsUntilAutoClaimAvailable) {
        account = _account;

        index = tokenHoldersMap.getIndexOfKey(account);

        iterationsUntilProcessed = -1;

        if(index >= 0) {
            if(uint256(index) > lastProcessedIndex) {
                iterationsUntilProcessed = index.sub(int256(lastProcessedIndex));
            }
            else {
                uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > lastProcessedIndex ?
                                                        tokenHoldersMap.keys.length.sub(lastProcessedIndex) :
                                                        0;


                iterationsUntilProcessed = index.add(int256(processesUntilEndOfArray));
            }
        }


        withdrawableDividends = withdrawableDividendOf(account);
        totalDividends = accumulativeDividendOf(account);

        lastClaimTime = lastClaimTimes[account];

        nextClaimTime = lastClaimTime > 0 ?
                                    lastClaimTime.add(claimWait) :
                                    0;

        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ?
                                                    nextClaimTime.sub(block.timestamp) :
                                                    0;
    }

    function getAccountAtIndex(uint256 index)
        public view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	if(index >= tokenHoldersMap.size()) {
            return (0x0000000000000000000000000000000000000000, -1, -1, 0, 0, 0, 0, 0);
        }

        address account = tokenHoldersMap.getKeyAtIndex(index);

        return getAccount(account);
    }

    function canAutoClaim(uint256 lastClaimTime) private view returns (bool) {
    	if(lastClaimTime > block.timestamp)  {
    		return false;
    	}

    	return block.timestamp.sub(lastClaimTime) >= claimWait;
    }

    function setBalance(address payable account, uint256 newBalance) external onlyOwner {
    	if(excludedFromDividends[account]) {
    		return;
    	}

    	if(newBalance >= minimumTokenBalanceForDividends) {
            _setBalance(account, newBalance);
    		tokenHoldersMap.set(account, newBalance);
    	}
    	else {
            _setBalance(account, 0);
    		tokenHoldersMap.remove(account);
    	}

    	processAccount(account, true);
    }

    function process(uint256 gas) public returns (uint256, uint256, uint256) {
    	uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

    	if(numberOfTokenHolders == 0) {
    		return (0, 0, lastProcessedIndex);
    	}

    	uint256 _lastProcessedIndex = lastProcessedIndex;

    	uint256 gasUsed = 0;

    	uint256 gasLeft = gasleft();

    	uint256 iterations = 0;
    	uint256 claims = 0;

    	while(gasUsed < gas && iterations < numberOfTokenHolders) {
    		_lastProcessedIndex++;

    		if(_lastProcessedIndex >= tokenHoldersMap.keys.length) {
    			_lastProcessedIndex = 0;
    		}

    		address account = tokenHoldersMap.keys[_lastProcessedIndex];

    		if(canAutoClaim(lastClaimTimes[account])) {
    			if(processAccount(payable(account), true)) {
    				claims++;
    			}
    		}

    		iterations++;

    		uint256 newGasLeft = gasleft();

    		if(gasLeft > newGasLeft) {
    			gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
    		}

    		gasLeft = newGasLeft;
    	}

    	lastProcessedIndex = _lastProcessedIndex;

    	return (iterations, claims, lastProcessedIndex);
    }

    function processAccount(address payable account, bool automatic) public onlyOwner returns (bool) {
        uint256 amount = _withdrawDividendOfUser(account);

    	if(amount > 0) {
    		lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
    		return true;
    	}

    	return false;
    }
}

contract PolkaDividendTracker is DividendPayingToken, Ownable {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public lastProcessedIndex;

    mapping (address => bool) public excludedFromDividends;

    mapping (address => uint256) public lastClaimTimes;

    uint256 public claimWait;
    uint256 public minimumTokenBalanceForDividends;

    event ExcludeFromDividends(address indexed account);
    event ClaimWaitUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event Claim(address indexed account, uint256 amount, bool indexed automatic);

    constructor() DividendPayingToken("DottyDoge_Polka_Dividend_Tracker", "DottyDoge_Polka_Dividend_Tracker", 0x7083609fCE4d1d8Dc0C979AAb8c869Ea2C873402) {
    	claimWait = 60;
        minimumTokenBalanceForDividends = 200000 * (10**12); //must hold 10000+ tokens
    }

    function _transfer(address, address, uint256) pure internal override {
        require(false, "DottyDoge_Polka_Dividend_Tracker: No transfers allowed");
    }

    function withdrawDividend() pure public override {
        require(false, "DottyDoge_Polka_Dividend_Tracker: withdrawDividend disabled. Use the 'claim' function on the main DottyDoge contract.");
    }
    
    function setDividendTokenAddress(address newToken) external override onlyOwner {
      dividendToken = newToken;
    }
    
    function updateMinimumTokenBalanceForDividends(uint256 _newMinimumBalance) external onlyOwner {
        require(_newMinimumBalance != minimumTokenBalanceForDividends, "New mimimum balance for dividend cannot be same as current minimum balance");
        minimumTokenBalanceForDividends = _newMinimumBalance * (10**12);
    }

    function excludeFromDividends(address account) external onlyOwner {
    	require(!excludedFromDividends[account]);
    	excludedFromDividends[account] = true;

    	_setBalance(account, 0);
    	tokenHoldersMap.remove(account);

    	emit ExcludeFromDividends(account);
    }

    function updateClaimWait(uint256 newClaimWait) external onlyOwner {
        require(newClaimWait != claimWait, "DottyDoge_Polka_Dividend_Tracker: Cannot update claimWait to same value");
        emit ClaimWaitUpdated(newClaimWait, claimWait);
        claimWait = newClaimWait;
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view returns(uint256) {
        return tokenHoldersMap.keys.length;
    }


    function getAccount(address _account)
        public view returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableDividends,
            uint256 totalDividends,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 secondsUntilAutoClaimAvailable) {
        account = _account;

        index = tokenHoldersMap.getIndexOfKey(account);

        iterationsUntilProcessed = -1;

        if(index >= 0) {
            if(uint256(index) > lastProcessedIndex) {
                iterationsUntilProcessed = index.sub(int256(lastProcessedIndex));
            }
            else {
                uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > lastProcessedIndex ?
                                                        tokenHoldersMap.keys.length.sub(lastProcessedIndex) :
                                                        0;


                iterationsUntilProcessed = index.add(int256(processesUntilEndOfArray));
            }
        }


        withdrawableDividends = withdrawableDividendOf(account);
        totalDividends = accumulativeDividendOf(account);

        lastClaimTime = lastClaimTimes[account];

        nextClaimTime = lastClaimTime > 0 ?
                                    lastClaimTime.add(claimWait) :
                                    0;

        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ?
                                                    nextClaimTime.sub(block.timestamp) :
                                                    0;
    }

    function getAccountAtIndex(uint256 index)
        public view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	if(index >= tokenHoldersMap.size()) {
            return (0x0000000000000000000000000000000000000000, -1, -1, 0, 0, 0, 0, 0);
        }

        address account = tokenHoldersMap.getKeyAtIndex(index);

        return getAccount(account);
    }

    function canAutoClaim(uint256 lastClaimTime) private view returns (bool) {
    	if(lastClaimTime > block.timestamp)  {
    		return false;
    	}

    	return block.timestamp.sub(lastClaimTime) >= claimWait;
    }

    function setBalance(address payable account, uint256 newBalance) external onlyOwner {
    	if(excludedFromDividends[account]) {
    		return;
    	}

    	if(newBalance >= minimumTokenBalanceForDividends) {
            _setBalance(account, newBalance);
    		tokenHoldersMap.set(account, newBalance);
    	}
    	else {
            _setBalance(account, 0);
    		tokenHoldersMap.remove(account);
    	}

    	processAccount(account, true);
    }

    function process(uint256 gas) public returns (uint256, uint256, uint256) {
    	uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

    	if(numberOfTokenHolders == 0) {
    		return (0, 0, lastProcessedIndex);
    	}

    	uint256 _lastProcessedIndex = lastProcessedIndex;

    	uint256 gasUsed = 0;

    	uint256 gasLeft = gasleft();

    	uint256 iterations = 0;
    	uint256 claims = 0;

    	while(gasUsed < gas && iterations < numberOfTokenHolders) {
    		_lastProcessedIndex++;

    		if(_lastProcessedIndex >= tokenHoldersMap.keys.length) {
    			_lastProcessedIndex = 0;
    		}

    		address account = tokenHoldersMap.keys[_lastProcessedIndex];

    		if(canAutoClaim(lastClaimTimes[account])) {
    			if(processAccount(payable(account), true)) {
    				claims++;
    			}
    		}

    		iterations++;

    		uint256 newGasLeft = gasleft();

    		if(gasLeft > newGasLeft) {
    			gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
    		}

    		gasLeft = newGasLeft;
    	}

    	lastProcessedIndex = _lastProcessedIndex;

    	return (iterations, claims, lastProcessedIndex);
    }

    function processAccount(address payable account, bool automatic) public onlyOwner returns (bool) {
        uint256 amount = _withdrawDividendOfUser(account);

    	if(amount > 0) {
    		lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
    		return true;
    	}

    	return false;
    }
}