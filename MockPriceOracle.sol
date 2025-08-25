// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockPriceOracle - 模拟价格预言机
 * @notice 用于测试的价格预言机，可以手动设置ETH价格
 * @dev 生产环境应使用Chainlink等真实预言机
 */
contract MockPriceOracle {
    uint256 public ethPriceInUSD;
    address public owner;
    uint256 public lastUpdateTime;
    
    // 价格历史记录
    struct PriceData {
        uint256 price;
        uint256 timestamp;
    }
    
    PriceData[] public priceHistory;
    uint256 public constant MAX_HISTORY = 100;
    
    event PriceUpdated(uint256 newPrice, uint256 timestamp);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        // 初始价格设为 2000 USD（带18位小数）
        ethPriceInUSD = 2000 * 10**18;
        lastUpdateTime = block.timestamp;
        
        // 记录初始价格
        priceHistory.push(PriceData({
            price: ethPriceInUSD,
            timestamp: block.timestamp
        }));
    }
    
    /**
     * @notice 获取最新的ETH价格
     * @return 当前ETH价格（18位小数）
     */
    function getLatestPrice() external view returns (uint256) {
        return ethPriceInUSD;
    }
    
    /**
     * @notice 手动更新价格（仅用于测试）
     * @param newPrice 新的ETH价格（需要包含18位小数）
     */
    function updatePrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be positive");
        require(newPrice < 1000000 * 10**18, "Price too high"); // 防止误操作
        
        ethPriceInUSD = newPrice;
        lastUpdateTime = block.timestamp;
        
        // 记录价格历史
        _addPriceHistory(newPrice);
        
        emit PriceUpdated(newPrice, block.timestamp);
    }
    
    /**
     * @notice 模拟价格波动
     * @param percentageChange 价格变化百分比（可以为负数）
     */
    function simulateVolatility(int256 percentageChange) external onlyOwner {
        require(percentageChange > -100 && percentageChange < 100, "Invalid percentage");
        
        int256 currentPrice = int256(ethPriceInUSD);
        int256 change = (currentPrice * percentageChange) / 100;
        int256 newPrice = currentPrice + change;
        
        require(newPrice > 0, "Price cannot be negative");
        require(newPrice < int256(1000000 * 10**18), "Price too high");
        
        ethPriceInUSD = uint256(newPrice);
        lastUpdateTime = block.timestamp;
        
        // 记录价格历史
        _addPriceHistory(uint256(newPrice));
        
        emit PriceUpdated(uint256(newPrice), block.timestamp);
    }
    
    /**
     * @notice 批量模拟价格波动
     * @param changes 价格变化百分比数组
     * @param intervals 每次变化之间的时间间隔（秒）
     */
    function simulateVolatilityBatch(int256[] calldata changes, uint256 intervals) external onlyOwner {
        require(changes.length > 0 && changes.length <= 10, "Invalid batch size");
        require(intervals >= 1 && intervals <= 3600, "Invalid interval");
        
        for (uint256 i = 0; i < changes.length; i++) {
            require(changes[i] > -50 && changes[i] < 50, "Change too extreme");
            
            int256 currentPrice = int256(ethPriceInUSD);
            int256 change = (currentPrice * changes[i]) / 100;
            int256 newPrice = currentPrice + change;
            
            require(newPrice > 0, "Price cannot be negative");
            
            ethPriceInUSD = uint256(newPrice);
            lastUpdateTime = block.timestamp + (i * intervals);
            
            _addPriceHistory(uint256(newPrice));
            
            emit PriceUpdated(uint256(newPrice), lastUpdateTime);
        }
    }
    
    /**
     * @notice 获取价格更新时间
     * @return 最后更新的时间戳
     */
    function getLastUpdateTime() external view returns (uint256) {
        return lastUpdateTime;
    }
    
    /**
     * @notice 检查价格是否过期
     * @param maxAge 最大允许的价格年龄（秒）
     * @return 价格是否仍然有效
     */
    function isPriceFresh(uint256 maxAge) external view returns (bool) {
        return block.timestamp <= lastUpdateTime + maxAge;
    }
    
    /**
     * @notice 获取价格历史记录数量
     * @return 历史记录条数
     */
    function getPriceHistoryLength() external view returns (uint256) {
        return priceHistory.length;
    }
    
    /**
     * @notice 获取特定索引的历史价格
     * @param index 历史记录索引
     * @return price 历史价格
     * @return timestamp 价格时间戳
     */
    function getPriceAt(uint256 index) external view returns (uint256 price, uint256 timestamp) {
        require(index < priceHistory.length, "Index out of bounds");
        PriceData memory data = priceHistory[index];
        return (data.price, data.timestamp);
    }
    
    /**
     * @notice 获取最近N条价格记录
     * @param count 要获取的记录数量
     * @return prices 价格数组
     * @return timestamps 时间戳数组
     */
    function getRecentPrices(uint256 count) external view returns (uint256[] memory prices, uint256[] memory timestamps) {
        uint256 length = priceHistory.length;
        if (count > length) {
            count = length;
        }
        
        prices = new uint256[](count);
        timestamps = new uint256[](count);
        
        for (uint256 i = 0; i < count; i++) {
            PriceData memory data = priceHistory[length - count + i];
            prices[i] = data.price;
            timestamps[i] = data.timestamp;
        }
        
        return (prices, timestamps);
    }
    
    /**
     * @notice 重置价格到初始值
     * @dev 仅用于测试环境
     */
    function resetPrice() external onlyOwner {
        ethPriceInUSD = 2000 * 10**18;
        lastUpdateTime = block.timestamp;
        
        _addPriceHistory(ethPriceInUSD);
        
        emit PriceUpdated(ethPriceInUSD, block.timestamp);
    }
    
    /**
     * @notice 转移所有权
     * @param newOwner 新的所有者地址
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    
    /**
     * @notice 内部函数：添加价格历史记录
     * @param price 要记录的价格
     */
    function _addPriceHistory(uint256 price) private {
        if (priceHistory.length >= MAX_HISTORY) {
            // 移除最旧的记录
            for (uint256 i = 0; i < priceHistory.length - 1; i++) {
                priceHistory[i] = priceHistory[i + 1];
            }
            priceHistory[priceHistory.length - 1] = PriceData({
                price: price,
                timestamp: block.timestamp
            });
        } else {
            priceHistory.push(PriceData({
                price: price,
                timestamp: block.timestamp
            }));
        }
    }
}