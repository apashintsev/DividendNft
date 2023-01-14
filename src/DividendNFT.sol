// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {BaseERC721A} from "./BaseERC721A.sol";
import {IERC721A, ERC721A} from "ERC721A/ERC721A.sol";

contract DividendNFT is BaseERC721A {
    string private FILENAME;
    uint256 public immutable PERIOD = 90 days;
    uint256 public finalTotalSupply = 100_000;
    uint256 public mintPrice;
    uint256 public membersCount; //здесь храним общее количество акционеров
    uint256 public nextComputeRewardsDate; //дата следующего рассчётного периода

    uint256 public fixedBalance;

    // With `magnitude`, we can properly distribute dividends even if the amount of received ether is small.
    // For more discussion about choosing the value of `magnitude`,
    //  see https://github.com/ethereum/EIPs/issues/1726#issuecomment-472352728
    uint256 public constant MAGNITUDE = 2**128;

    uint256 public magnifiedDividendPerShare;

    uint256 public phase; //раунд выплат

    //здесь храним сколько юзер получил дивидендов на текущей фазе (текущая-1)
    //если он на текущей фазе получал, то больше на этой фазе получить не может, блокируем
    //если дивы получил и передал часть токенов другому, то у этого другого так же увеличиваем это значение
    //при рассчёте дивов всегда отнимаем это значение
    //при минте так же увеличиваем это значение
    mapping(uint256 => mapping(address => uint256)) public claimedAtPhase;
    mapping(uint256 => mapping(address => bool)) public hasClaimedAtPhase;

    event DividendsComputed(
        uint256 indexed computeDate,
        uint256 dividendPerShare,
        uint256 nextComputeRewardsDate
    );

    error NoRewards();
    error NotEnoughtFundsInContract();
    error CantTransferFunds();
    error FinalTotalSupplyReached();
    error IncorrectEtherValueSended();
    error AllreadyClaimedAtThisPhase();

    constructor(
        string memory name_,
        string memory symbol_,
        string memory filename_
    ) BaseERC721A(name_, symbol_) {
        _mint(msg.sender, 50_000);
        FILENAME = filename_;
        mintPrice = 0.00001 ether;
        nextComputeRewardsDate = block.timestamp + PERIOD;
    }

    /**
     * @dev Принять эфир от пользователя и выдать ему токены
     */
    function mint(uint256 quantity) public payable {
        if (totalSupply() + quantity >= finalTotalSupply) {
            revert FinalTotalSupplyReached();
        }
        if (mintPrice * quantity != msg.value) {
            revert IncorrectEtherValueSended();
        }
        (bool success, ) = payable(owner()).call{value: msg.value}(""); // плата за нфт отправляется владельцу
        if (!success) {
            revert CantTransferFunds();
        }
        claimedAtPhase[phase][msg.sender] +=
            (quantity * magnifiedDividendPerShare) /
            MAGNITUDE;
        super._mint(msg.sender, quantity); //todo to safemint
    }

    function setMintPrice(uint256 newPrice) external onlyOwner {
        //require(newPrice > tokenPrice, "Must be greater than last");
        mintPrice = newPrice;
    }

    //баланс контракта
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getAllowedWithdrawAmount() public view returns (uint256) {
        return _getAllowedWithdrawAmount(msg.sender);
    }

    /**
     * @dev вывести доступные для вывода средства забрать награду за нфт
     */
    function withdrawRewards() external {
        uint256 reward = _getAllowedWithdrawAmount(msg.sender);
        if (reward == 0) {
            revert NoRewards();
        }
        if (reward > fixedBalance) {
            //такого не должно быть
            revert NotEnoughtFundsInContract();
        }
        if (hasClaimedAtPhase[phase][msg.sender]) {
            revert AllreadyClaimedAtThisPhase();
        }
        hasClaimedAtPhase[phase][msg.sender] = true;
        fixedBalance -= reward;
        claimedAtPhase[phase][msg.sender] += reward;
        (bool success, ) = payable(msg.sender).call{value: reward}("");
        if (!success) {
            revert CantTransferFunds();
        }
    }

    /*
     * рассчитать сколько дивов юзер может сейчас выводить
     */
    function _getAllowedWithdrawAmount(address user)
        private
        view
        returns (uint256)
    {
        uint256 usersAmount = (balanceOf(user) * magnifiedDividendPerShare) /
            MAGNITUDE;
        return usersAmount - claimedAtPhase[phase][user];
    }

    /**
     * @dev рассчитать сколько дивов сейчас полагается
     */
    function computeRewards() public {
        if (nextComputeRewardsDate < block.timestamp) {
            require(totalSupply() > 0);
            nextComputeRewardsDate += PERIOD;
            magnifiedDividendPerShare =
                (fixedBalance * MAGNITUDE) /
                totalSupply();
            phase += 1;
            emit DividendsComputed(
                block.timestamp,
                magnifiedDividendPerShare / MAGNITUDE,
                nextComputeRewardsDate
            );
        }
    }

    /**
     * @dev пополнить контракт
     */
    receive() external payable {
        fixedBalance += msg.value;
        computeRewards();
    }

    //overrides
    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
        //здесь проверим добавлен ли уже этот пользователь в список акционеров
        if (balanceOf(to) == 0 && quantity > 0) {
            membersCount++;
        }
    }

    function _afterTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        super._afterTokenTransfers(from, to, startTokenId, quantity);
        //если не минт с 0 адреса, а у отправителя после отправки не осталось токенов, то уменьшим кол-во акционеров
        if (from != address(0) && balanceOf(from) == 0) {
            membersCount--;
        }
        //здесь поставим защиту от двойного вывода дивидендов
        if (claimedAtPhase[phase][from] > 0) {
            //если отправитель выводил дивы, тогда скорректируем у получателя
            claimedAtPhase[phase][to] +=
                (quantity * magnifiedDividendPerShare) /
                MAGNITUDE;
        }
    }

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721A, IERC721A)
        returns (string memory)
    {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        string memory baseURI = _baseURI();
        return
            bytes(baseURI).length != 0
                ? string(abi.encodePacked(baseURI, FILENAME))
                : "";
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return "ipfs://";
    }
}
