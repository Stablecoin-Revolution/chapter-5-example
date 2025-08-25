// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title 接口定义
 * @notice 定义与其他合约交互所需的接口
 */
interface ISimpleUSD {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IPriceOracle {
    function getLatestPrice() external view returns (uint256);
    function isPriceFresh(uint256 maxAge) external view returns (bool);
}

/**
 * @title StablecoinVault - 稳定币金库系统
 * @notice 管理抵押品、铸造稳定币、执行清算
 * @dev 教学版本，简化了很多生产环境的复杂性
 */
contract StablecoinVault {
    ISimpleUSD public immutable stablecoin;
    IPriceOracle public immutable priceOracle;
    
    // 系统参数
    uint256 public constant COLLATERAL_RATIO = 150; // 150%最低抵押率
    uint256 public constant LIQUIDATION_THRESHOLD = 130; // 130%清算线
    uint256 public constant LIQUIDATION_BONUS = 5; // 5%清算奖励
    uint256 public constant PRECISION = 10**18;
    uint256 public constant MIN_DEBT = 10 * 10**18; // 最小债务10 SUSD
    uint256 public constant PRICE_FRESHNESS = 3600; // 价格有效期1小时
    
    // 用户金库
    struct Vault {
        uint256 collateralAmount;  // 抵押的ETH数量
        uint256 debtAmount;        // 借出的稳定币数量
    }
    
    mapping(address => Vault) public vaults;
    
    // 系统统计
    uint256 public totalCollateral;
    uint256 public totalDebt;
    uint256 public totalLiquidations;
    
    // 用户列表（用于前端查询）
    address[] public vaultOwners;
    mapping(address => bool) public hasVault;
    
    // 事件
    event VaultOpened(address indexed user, uint256 collateral, uint256 debt);
    event VaultClosed(address indexed user);
    event CollateralAdded(address indexed user, uint256 amount);
    event CollateralRemoved(address indexed user, uint256 amount);
    event DebtIncreased(address indexed user, uint256 amount);
    event DebtDecreased(address indexed user, uint256 amount);
    event VaultLiquidated(
        address indexed user, 
        address indexed liquidator, 
        uint256 debtCovered, 
        uint256 collateralSeized
    );
    
    // 错误定义
    error InsufficientCollateral();
    error VaultNotLiquidatable();
    error PriceStale();
    error AmountTooSmall();
    error TransferFailed();
    
    constructor(address _stablecoin, address _priceOracle) {
        require(_stablecoin != address(0), "Invalid stablecoin address");
        require(_priceOracle != address(0), "Invalid oracle address");
        
        stablecoin = ISimpleUSD(_stablecoin);
        priceOracle = IPriceOracle(_priceOracle);
    }
    
    // ========== 核心功能 ==========
    
    /**
     * @notice 抵押ETH并铸造稳定币
     * @param mintAmount 要铸造的稳定币数量
     */
    function depositAndMint(uint256 mintAmount) external payable {
        require(msg.value > 0, "Must deposit ETH");
        require(mintAmount >= MIN_DEBT, "Mint amount too small");
        
        // 检查价格是否新鲜
        if (!priceOracle.isPriceFresh(PRICE_FRESHNESS)) {
            revert PriceStale();
        }
        
        // 获取ETH价格
        uint256 ethPrice = priceOracle.getLatestPrice();
        
        // 计算抵押品价值
        uint256 collateralValueInUSD = (msg.value * ethPrice) / PRECISION;
        
        // 检查抵押率
        uint256 requiredCollateral = (mintAmount * COLLATERAL_RATIO) / 100;
        if (collateralValueInUSD < requiredCollateral) {
            revert InsufficientCollateral();
        }
        
        // 如果是新用户，添加到列表
        if (!hasVault[msg.sender]) {
            vaultOwners.push(msg.sender);
            hasVault[msg.sender] = true;
        }
        
        // 更新金库
        vaults[msg.sender].collateralAmount += msg.value;
        vaults[msg.sender].debtAmount += mintAmount;
        
        // 更新系统统计
        totalCollateral += msg.value;
        totalDebt += mintAmount;
        
        // 铸造稳定币
        stablecoin.mint(msg.sender, mintAmount);
        
        emit VaultOpened(msg.sender, msg.value, mintAmount);
        emit DebtIncreased(msg.sender, mintAmount);
    }
    
    /**
     * @notice 偿还稳定币并取回抵押品
     * @param repayAmount 要偿还的稳定币数量
     */
    function repayAndWithdraw(uint256 repayAmount) external {
        Vault storage vault = vaults[msg.sender];
        require(repayAmount > 0, "Must repay something");
        require(vault.debtAmount >= repayAmount, "Repay exceeds debt");
        
        // 从用户账户转入稳定币
        bool success = stablecoin.transferFrom(msg.sender, address(this), repayAmount);
        require(success, "Transfer failed");
        
        // 销毁稳定币
        stablecoin.burn(repayAmount);
        
        uint256 collateralToReturn;
        
        if (repayAmount == vault.debtAmount) {
            // 全部偿还，返回所有抵押品
            collateralToReturn = vault.collateralAmount;
            vault.collateralAmount = 0;
            vault.debtAmount = 0;
            
            emit VaultClosed(msg.sender);
        } else {
            // 部分偿还
            vault.debtAmount -= repayAmount;
            
            // 检查剩余债务是否满足最小要求
            require(vault.debtAmount >= MIN_DEBT, "Remaining debt too small");
            
            // 计算可以安全取回的抵押品
            uint256 ethPrice = priceOracle.getLatestPrice();
            uint256 requiredCollateral = (vault.debtAmount * COLLATERAL_RATIO * PRECISION) / (100 * ethPrice);
            
            require(vault.collateralAmount > requiredCollateral, "No excess collateral");
            
            // 计算多余的抵押品
            uint256 excessCollateral = vault.collateralAmount - requiredCollateral;
            
            // 保守起见，只返回80%的多余抵押品
            collateralToReturn = (excessCollateral * 80) / 100;
            
            vault.collateralAmount -= collateralToReturn;
        }
        
        // 更新系统统计
        totalDebt -= repayAmount;
        totalCollateral -= collateralToReturn;
        
        // 返还ETH
        (bool sent, ) = msg.sender.call{value: collateralToReturn}("");
        if (!sent) {
            revert TransferFailed();
        }
        
        emit DebtDecreased(msg.sender, repayAmount);
        emit CollateralRemoved(msg.sender, collateralToReturn);
    }
    
    /**
     * @notice 添加更多抵押品
     */
    function addCollateral() external payable {
        require(msg.value > 0, "Must add collateral");
        require(hasVault[msg.sender], "No vault exists");
        
        vaults[msg.sender].collateralAmount += msg.value;
        totalCollateral += msg.value;
        
        emit CollateralAdded(msg.sender, msg.value);
    }
    
    /**
     * @notice 借出更多稳定币
     * @param mintAmount 额外要铸造的稳定币数量
     */
    function mintMore(uint256 mintAmount) external {
        require(mintAmount > 0, "Must mint something");
        
        Vault storage vault = vaults[msg.sender];
        require(vault.collateralAmount > 0, "No collateral");
        
        // 检查价格是否新鲜
        if (!priceOracle.isPriceFresh(PRICE_FRESHNESS)) {
            revert PriceStale();
        }
        
        // 检查新的抵押率
        uint256 ethPrice = priceOracle.getLatestPrice();
        uint256 newDebt = vault.debtAmount + mintAmount;
        uint256 collateralValue = (vault.collateralAmount * ethPrice) / PRECISION;
        uint256 newRatio = (collateralValue * 100) / newDebt;
        
        require(newRatio >= COLLATERAL_RATIO, "Would break min ratio");
        
        vault.debtAmount = newDebt;
        totalDebt += mintAmount;
        
        stablecoin.mint(msg.sender, mintAmount);
        
        emit DebtIncreased(msg.sender, mintAmount);
    }
    
    /**
     * @notice 移除部分抵押品
     * @param amount 要移除的ETH数量
     */
    function removeCollateral(uint256 amount) external {
        Vault storage vault = vaults[msg.sender];
        require(amount > 0, "Amount must be positive");
        require(vault.collateralAmount >= amount, "Insufficient collateral");
        
        // 如果有债务，检查移除后的抵押率
        if (vault.debtAmount > 0) {
            uint256 ethPrice = priceOracle.getLatestPrice();
            uint256 newCollateral = vault.collateralAmount - amount;
            uint256 collateralValue = (newCollateral * ethPrice) / PRECISION;
            uint256 newRatio = (collateralValue * 100) / vault.debtAmount;
            
            require(newRatio >= COLLATERAL_RATIO, "Would break min ratio");
        }
        
        vault.collateralAmount -= amount;
        totalCollateral -= amount;
        
        (bool sent, ) = msg.sender.call{value: amount}("");
        if (!sent) {
            revert TransferFailed();
        }
        
        emit CollateralRemoved(msg.sender, amount);
    }
    
    // ========== 清算功能 ==========
    
    /**
     * @notice 检查金库是否可被清算
     * @param user 要检查的用户地址
     */
    function isLiquidatable(address user) public view returns (bool) {
        Vault memory vault = vaults[user];
        if (vault.debtAmount == 0) return false;
        
        uint256 ratio = getCollateralRatio(user);
        return ratio < LIQUIDATION_THRESHOLD;
    }
    
    /**
     * @notice 清算不健康的金库
     * @param user 要清算的用户地址
     * @param debtToCover 清算人愿意偿还的债务数量
     */
    function liquidate(address user, uint256 debtToCover) external {
        if (!isLiquidatable(user)) {
            revert VaultNotLiquidatable();
        }
        
        Vault storage vault = vaults[user];
        
        // 确定实际要清算的债务数量
        if (debtToCover > vault.debtAmount) {
            debtToCover = vault.debtAmount;
        }
        
        // 从清算人转入稳定币
        bool success = stablecoin.transferFrom(msg.sender, address(this), debtToCover);
        require(success, "Transfer failed");
        
        // 销毁稳定币
        stablecoin.burn(debtToCover);
        
        // 计算清算人获得的抵押品（包含奖励）
        uint256 ethPrice = priceOracle.getLatestPrice();
        uint256 collateralValue = (debtToCover * (100 + LIQUIDATION_BONUS) * PRECISION) / (100 * ethPrice);
        
        // 确保不会拿走过多抵押品
        if (collateralValue > vault.collateralAmount) {
            collateralValue = vault.collateralAmount;
            debtToCover = (collateralValue * ethPrice * 100) / ((100 + LIQUIDATION_BONUS) * PRECISION);
        }
        
        // 更新金库
        vault.debtAmount -= debtToCover;
        vault.collateralAmount -= collateralValue;
        
        // 更新系统统计
        totalDebt -= debtToCover;
        totalCollateral -= collateralValue;
        totalLiquidations++;
        
        // 如果金库被完全清算，关闭它
        if (vault.debtAmount == 0) {
            // 返还剩余的抵押品给原所有者
            if (vault.collateralAmount > 0) {
                uint256 remaining = vault.collateralAmount;
                vault.collateralAmount = 0;
                totalCollateral -= remaining;
                
                (bool sentToOwner, ) = user.call{value: remaining}("");
                // 如果发送失败，保留在合约中
                if (sentToOwner) {
                    emit CollateralRemoved(user, remaining);
                }
            }
            emit VaultClosed(user);
        }
        
        // 转移抵押品给清算人
        (bool sentToLiquidator, ) = msg.sender.call{value: collateralValue}("");
        if (!sentToLiquidator) {
            revert TransferFailed();
        }
        
        emit VaultLiquidated(user, msg.sender, debtToCover, collateralValue);
    }
    
    // ========== 查询功能 ==========
    
    /**
     * @notice 获取用户的抵押率
     * @param user 用户地址
     * @return 抵押率（百分比）
     */
    function getCollateralRatio(address user) public view returns (uint256) {
        Vault memory vault = vaults[user];
        if (vault.debtAmount == 0) return type(uint256).max;
        
        uint256 ethPrice = priceOracle.getLatestPrice();
        uint256 collateralValue = (vault.collateralAmount * ethPrice) / PRECISION;
        return (collateralValue * 100) / vault.debtAmount;
    }
    
    /**
     * @notice 获取金库详细信息
     */
    function getVaultInfo(address user) external view returns (
        uint256 collateral,
        uint256 debt,
        uint256 collateralValue,
        uint256 ratio,
        bool liquidatable
    ) {
        Vault memory vault = vaults[user];
        uint256 ethPrice = priceOracle.getLatestPrice();
        
        collateral = vault.collateralAmount;
        debt = vault.debtAmount;
        collateralValue = (collateral * ethPrice) / PRECISION;
        ratio = debt > 0 ? (collateralValue * 100) / debt : type(uint256).max;
        liquidatable = ratio < LIQUIDATION_THRESHOLD && debt > 0;
    }
    
    /**
     * @notice 获取系统整体状态
     */
    function getSystemStatus() external view returns (
        uint256 totalCol,
        uint256 totalDbt,
        uint256 systemRatio,
        uint256 currentETHPrice,
        uint256 totalLiq
    ) {
        totalCol = totalCollateral;
        totalDbt = totalDebt;
        currentETHPrice = priceOracle.getLatestPrice();
        totalLiq = totalLiquidations;
        
        if (totalDbt > 0) {
            uint256 totalValue = (totalCol * currentETHPrice) / PRECISION;
            systemRatio = (totalValue * 100) / totalDbt;
        } else {
            systemRatio = type(uint256).max;
        }
    }
    
    /**
     * @notice 获取所有金库拥有者数量
     */
    function getVaultOwnersCount() external view returns (uint256) {
        return vaultOwners.length;
    }
    
    /**
     * @notice 获取指定范围的金库拥有者地址
     * @param start 起始索引
     * @param end 结束索引（不包含）
     */
    function getVaultOwners(uint256 start, uint256 end) external view returns (address[] memory) {
        require(start < end, "Invalid range");
        require(end <= vaultOwners.length, "End exceeds length");
        
        uint256 length = end - start;
        address[] memory owners = new address[](length);
        
        for (uint256 i = 0; i < length; i++) {
            owners[i] = vaultOwners[start + i];
        }
        
        return owners;
    }
    
    /**
     * @notice 批量获取多个用户的抵押率
     * @param users 用户地址数组
     * @return ratios 抵押率数组
     */
    function getCollateralRatioBatch(address[] calldata users) external view returns (uint256[] memory ratios) {
        ratios = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            ratios[i] = getCollateralRatio(users[i]);
        }
        return ratios;
    }
    
    /**
     * @notice 查找所有可清算的金库
     * @param maxResults 最大返回结果数
     * @return liquidatableUsers 可清算的用户地址
     * @return ratios 对应的抵押率
     */
    function getLiquidatableVaults(uint256 maxResults) external view returns (
        address[] memory liquidatableUsers,
        uint256[] memory ratios
    ) {
        uint256 count = 0;
        address[] memory tempUsers = new address[](maxResults);
        uint256[] memory tempRatios = new uint256[](maxResults);
        
        for (uint256 i = 0; i < vaultOwners.length && count < maxResults; i++) {
            address user = vaultOwners[i];
            if (isLiquidatable(user)) {
                tempUsers[count] = user;
                tempRatios[count] = getCollateralRatio(user);
                count++;
            }
        }
        
        // 创建正确大小的数组
        liquidatableUsers = new address[](count);
        ratios = new uint256[](count);
        
        for (uint256 i = 0; i < count; i++) {
            liquidatableUsers[i] = tempUsers[i];
            ratios[i] = tempRatios[i];
        }
        
        return (liquidatableUsers, ratios);
    }
    
    /**
     * @notice 计算清算某个金库的收益
     * @param user 要清算的用户地址
     * @param debtToCover 打算偿还的债务数量
     * @return profit 预期收益（ETH）
     */
    function calculateLiquidationProfit(address user, uint256 debtToCover) external view returns (uint256 profit) {
        if (!isLiquidatable(user)) {
            return 0;
        }
        
        Vault memory vault = vaults[user];
        if (debtToCover > vault.debtAmount) {
            debtToCover = vault.debtAmount;
        }
        
        uint256 ethPrice = priceOracle.getLatestPrice();
        uint256 collateralToReceive = (debtToCover * (100 + LIQUIDATION_BONUS) * PRECISION) / (100 * ethPrice);
        
        if (collateralToReceive > vault.collateralAmount) {
            collateralToReceive = vault.collateralAmount;
        }
        
        uint256 debtValue = (debtToCover * PRECISION) / ethPrice;
        profit = collateralToReceive > debtValue ? collateralToReceive - debtValue : 0;
    }
    
    // ========== 紧急功能 ==========
    
    /**
     * @notice 紧急提取ETH（仅在极端情况下使用）
     * @dev 只能提取没有对应债务的多余ETH
     */
    function emergencyWithdraw() external {
        uint256 balance = address(this).balance;
        require(balance > totalCollateral, "No excess ETH");
        
        uint256 excess = balance - totalCollateral;
        (bool sent, ) = msg.sender.call{value: excess}("");
        require(sent, "Transfer failed");
    }
}