// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SimpleUSD - 教学用稳定币
 * @notice 这是一个简化的稳定币实现，用于学习目的
 * @dev 基于ERC20标准，添加了铸造和销毁功能
 */
contract SimpleUSD {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 private _totalSupply;
    string public constant name = "Simple USD";
    string public constant symbol = "SUSD";
    uint8 public constant decimals = 18;
    
    address public minter;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event MinterChanged(address indexed oldMinter, address indexed newMinter);
    
    modifier onlyMinter() {
        require(msg.sender == minter, "Only minter can call");
        _;
    }
    
    constructor() {
        minter = msg.sender;
    }
    
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) public returns (bool) {
        require(to != address(0), "Transfer to zero address");
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) public returns (bool) {
        require(spender != address(0), "Approve to zero address");
        
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
        
        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
    
    /**
     * @notice 铸造新的稳定币
     * @dev 只有minter地址可以调用此函数
     * @param to 接收新铸造代币的地址
     * @param amount 要铸造的代币数量
     */
    function mint(address to, uint256 amount) external onlyMinter {
        require(to != address(0), "Mint to zero address");
        require(amount > 0, "Amount must be positive");
        
        _totalSupply += amount;
        _balances[to] += amount;
        
        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }
    
    /**
     * @notice 销毁代币
     * @dev 任何人都可以销毁自己的代币
     * @param amount 要销毁的代币数量
     */
    function burn(uint256 amount) external {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        require(amount > 0, "Amount must be positive");
        
        _balances[msg.sender] -= amount;
        _totalSupply -= amount;
        
        emit Burn(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
    }
    
    /**
     * @notice 销毁特定地址的代币
     * @dev 需要先获得授权
     * @param from 要销毁代币的地址
     * @param amount 要销毁的代币数量
     */
    function burnFrom(address from, uint256 amount) external {
        require(from != address(0), "Burn from zero address");
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
        require(amount > 0, "Amount must be positive");
        
        _balances[from] -= amount;
        _totalSupply -= amount;
        _allowances[from][msg.sender] -= amount;
        
        emit Burn(from, amount);
        emit Transfer(from, address(0), amount);
    }
    
    /**
     * @notice 更新minter地址
     * @dev 只有当前minter可以转移铸币权
     * @param newMinter 新的minter地址
     */
    function setMinter(address newMinter) external onlyMinter {
        require(newMinter != address(0), "New minter is zero address");
        address oldMinter = minter;
        minter = newMinter;
        emit MinterChanged(oldMinter, newMinter);
    }
    
    /**
     * @notice 增加授权额度
     * @param spender 被授权的地址
     * @param addedValue 要增加的额度
     */
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        require(spender != address(0), "Spender is zero address");
        
        _allowances[msg.sender][spender] += addedValue;
        emit Approval(msg.sender, spender, _allowances[msg.sender][spender]);
        return true;
    }
    
    /**
     * @notice 减少授权额度
     * @param spender 被授权的地址
     * @param subtractedValue 要减少的额度
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        require(spender != address(0), "Spender is zero address");
        require(_allowances[msg.sender][spender] >= subtractedValue, "Decreased allowance below zero");
        
        _allowances[msg.sender][spender] -= subtractedValue;
        emit Approval(msg.sender, spender, _allowances[msg.sender][spender]);
        return true;
    }
}