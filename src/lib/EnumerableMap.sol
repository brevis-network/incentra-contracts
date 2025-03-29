// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

library EnumerableMap {
    using EnumerableSet for EnumerableSet.AddressSet;

    error EnumerableMapNonexistentKey(address key);

    struct UserTokenAmountMap {
        // Storage of keys
        EnumerableSet.AddressSet _keys;
        mapping(address key => mapping(address => uint256)) _values;
    }

    function set(UserTokenAmountMap storage map, address user, address token, uint256 amount, bool enumerable)
        internal
    {
        map._values[user][token] = amount;
        if (enumerable) {
            map._keys.add(user);
        }
    }

    function add(UserTokenAmountMap storage map, address user, address token, uint256 amount, bool enumerable)
        internal
    {
        map._values[user][token] += amount;
        if (enumerable) {
            map._keys.add(user);
        }
    }

    function contains(UserTokenAmountMap storage map, address user) internal view returns (bool) {
        return map._keys.contains(user);
    }

    function length(UserTokenAmountMap storage map) internal view returns (uint256) {
        return map._keys.length();
    }

    function at(UserTokenAmountMap storage map, uint256 index)
        internal
        view
        returns (address key, mapping(address => uint256) storage tokenAmountMap)
    {
        address atKey = map._keys.at(index);
        return (atKey, map._values[atKey]);
    }

    function get(UserTokenAmountMap storage map, address user, address token) internal view returns (uint256 amount) {
        mapping(address => uint256) storage tokenAmountMap = map._values[user];
        return tokenAmountMap[token];
    }

    function getAmounts(UserTokenAmountMap storage map, address user, address[] memory tokens)
        internal
        view
        returns (uint256[] memory amounts)
    {
        mapping(address => uint256) storage tokenAmountMap = map._values[user];
        amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = tokenAmountMap[tokens[i]];
        }
    }

    function getUserAmountsAt(UserTokenAmountMap storage map, uint256 index, address[] memory rewardTokens)
        internal
        view
        returns (address, uint256[] memory)
    {
        (address user, mapping(address => uint256) storage tokenAmountMap) = at(map, index);
        uint256[] memory amounts = new uint256[](rewardTokens.length);
        for (uint256 j = 0; j < rewardTokens.length; j++) {
            amounts[j] = tokenAmountMap[rewardTokens[j]];
        }
        return (user, amounts);
    }
}
