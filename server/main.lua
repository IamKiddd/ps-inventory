-- Variables

local QBCore = exports['qb-core']:GetCoreObject()
local Drops = {}
local Trunks = {}
local Gloveboxes = {}
local Stashes = {}
local ShopItems = {}
local inv = {}
-- Functions
---Loads the inventory for the player with the citizenid that is provided

CreateThread(function()
	while GetResourceState("oxmysql") ~= "started" do
        Wait(100)
    end
	local plate = MySQL.Sync.fetchAll('SELECT plate FROM player_vehicles')
	local plates = {}
	local inventory = MySQL.Sync.fetchAll('SELECT count(item_name) as amount, item_name, id, owner, information, slot, quality, MIN(creationDate) as creationDate FROM user_inventory2 group by item_name, slot, owner')
	inv = {}
	for _, row in ipairs(plate) do
		table.insert(plates, row.plate)
	end
	local update_data = {}
	local query = "DELETE FROM user_inventory2 WHERE item_name = ? AND slot = ?"
	for i, row in ipairs(inventory) do
		local name = row.name
		if not inv[name] then
			inv[name] = {}
		end
		if QBCore.Shared.SplitStr(name, "-")[1] ~= "Trunk" and QBCore.Shared.SplitStr(name, "-")[1] ~= "GloveBox" and QBCore.Shared.SplitStr(name, "-")[1] ~= "Drop" then
			table.insert(inv[name], row)
		else
			local shouldDelete = true
			for _, plate in ipairs(plates) do
				if name == 'Trunk-'..plate or name == 'GloveBox-'..plate then
					shouldDelete = false
					break
				end
			end
			if shouldDelete then
				inv[name] = nil
				update_data[#update_data + 1] = {  query = query, values = {row.item_name, row.slot  } }
			else
				table.insert(inv[name], row)
			end
		end
	end
	if #update_data > 0 then
		MySQL.transaction(update_data, function(result2)
			if result2 then
				print("Delete items in the trunk and glovebox that don't have owner")
			end
		end)
	end
	print("[ps-inventory] Loaded Item")
end)

local function ChangeSlot(item, name, from, to, amount)
	MySQL.query.await('UPDATE user_inventory2 SET slot = ? WHERE owner = ? AND slot = ? AND item_name = ? LIMIT ?' , {to, name, from, item,amount})
	local item = MySQL.Sync.fetchAll('SELECT count(item_name) as amount, item_name, id, owner, information, slot, quality, MIN(creationDate) as creationDate FROM user_inventory2 WHERE owner= ? group by item_name, slot, owner', {name})
	inv[name] = item
end

local function ChangeInv(item, fromInv, fromSlot, toSlot, toInv, amount)
	MySQL.query.await('UPDATE user_inventory2 SET name = ?, slot = ? WHERE owner = ? AND slot = ? AND item_name = ? LIMIT ?' , {toInv, toSlot, fromInv, fromSlot, item, amount})
	local item = MySQL.Sync.fetchAll('SELECT count(item_name) as amount, item_name, id, owner, information, slot, quality, MIN(creationDate) as creationDate FROM user_inventory2 WHERE owner = ? group by item_name, slot, owner', {fromInv})
	inv[fromInv] = item
	local item2 = MySQL.Sync.fetchAll('SELECT count(item_name) as amount, item_name, id, owner , information, slot, quality, MIN(creationDate) as creationDate FROM user_inventory2 WHERE owner = ? group by item_name, slot, owner', {toInv})
	inv[toInv] = item2
end

-- Decay System

local TimeAllowed = 60 * 60 * 24 * 1 -- Maths for 1 day dont touch its very important and could break everything
local function ConvertQuality(item)
	local StartDate = item.created
    local DecayRate = QBCore.Shared.Items[item.name:lower()]["decay"] ~= nil and QBCore.Shared.Items[item.name:lower()]["decay"] or 1.0
    if DecayRate == 0 or DecayRate == 0.0 then
        return item.quality
    end
    local TimeExtra = math.ceil((TimeAllowed * DecayRate))
	local decay = math.ceil((((os.time() - StartDate) / TimeExtra) * 100))
    local percentDone = item.quality - decay
    if percentDone < 0 then
        percentDone = 0
	elseif percentDone > 100 then
		percentDone = 100
	end
    return percentDone
end

local function ConvertQualityInv(inventory)
	local inv = inventory
	for _, item in pairs(inv) do
		if item.created then
			if QBCore.Shared.Items[item.name:lower()]["decay"] ~= nil or QBCore.Shared.Items[item.name:lower()]["decay"] ~= 0 then
				local quality = ConvertQuality(item)
				inv[_].quality = quality
			end
		end
	end
	return inv
end

local function BuildInventory(inventory)
	local loadedInventory = {}
	local missingItems = {}
    if not inventory then return loadedInventory end
	if table.type(inventory) == "empty" then return loadedInventory end
	for _, item in pairs(inventory) do
		if item then
			local itemInfo = QBCore.Shared.Items[item.item_name:lower()]
			if itemInfo then
				loadedInventory[item.slot] = {
					id = item.id,
					name = item.item_name,
					amount = item.amount,
					info = json.decode(item.information) or '',
					label = itemInfo['label'],
					description = itemInfo['description'] or '',
					weight = itemInfo['weight'],
					type = itemInfo['type'],
					unique = itemInfo['unique'],
					useable = itemInfo['useable'],
					image = itemInfo['image'],
					shouldClose = itemInfo['shouldClose'],
					slot = item.slot,
					combinable = itemInfo['combinable'],
					quality = item.quality or 100,
					created = item.creationDate,
				}
			else
				missingItems[#missingItems + 1] = item.item_name:lower()
			end
		end
	end

    if #missingItems > 0 then
        print(("The following items were removed for player %s as they no longer exist"):format(GetPlayerName(source)))
		QBCore.Debug(missingItems)
    end

    return loadedInventory
end

local function LoadInventory(source, citizenid)
	print('not use - load inventory', source, citizenid)
end

exports("LoadInventory", LoadInventory)

---Saves the inventory for the player with the provided source or PlayerData is they're offline

local function SaveInventory(source, offline)
	print('not use - save inventory', source, offline)
end

exports("SaveInventory", SaveInventory)

---Gets the totalweight of the items provided

local function GetTotalWeight(items)
	local weight = 0
    if not items then return 0 end
    for _, item in pairs(items) do
        weight += item.weight * item.amount
    end
    return tonumber(weight)
end

exports("GetTotalWeight", GetTotalWeight)

---Gets the slots that the provided item is in

local function GetSlotsByItem(items, itemName)
    local slotsFound = {}
	local amount = 0
    if not items then return slotsFound end
    for slot, item in pairs(items) do
        if item.name:lower() == itemName:lower() then
			amount += item.amount
            slotsFound[#slotsFound+1] = slot
        end
    end
    return slotsFound, amount
end

exports("GetSlotsByItem", GetSlotsByItem)

---Get the first slot where the item is located
local function countPairs(table)
	local count = 0
	for key, value in pairs(table) do
	  count = count + 1
	end
	return count
end

local function compareArrays(table1, table2)
	if countPairs(table1) ~= countPairs(table2) then
	  return false
	end
	for k, v in pairs (table1) do
		if table2[k] then
			if table1[k] ~= table2[k] then
				return false
			end
		else
			return false
		end
	end
	return true
end

local function GetFirstSlotByItem(items, itemName, info)
    if not items then return nil end
	if QBCore.Shared.Items[itemName:lower()]['unique'] then return nil end
	if QBCore.Shared.Items[itemName:lower()]['type'] == 'weapon' then return nil end
    for slot, item in pairs(items) do
        if item.name:lower() == itemName:lower() then
			if info then
				local info1 = compareArrays(info, item.info)
				if info1 then
					return tonumber(slot)
				end
			else
				return tonumber(slot)
			end
        end
    end
    return nil
end

exports("GetFirstSlotByItem", GetFirstSlotByItem)

---Add an item to the inventory of the player

local function AddItem(source, item, amount, slot, info, created)
	local Player = QBCore.Functions.GetPlayer(source)
	if not Player then return false end
	local totalWeight = GetTotalWeight(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
	local itemInfo = QBCore.Shared.Items[item:lower()]
	if not itemInfo and not Player.Offline then
		QBCore.Functions.Notify(source, "Item does not exist", 'error')
		return false
	end
	amount = tonumber(amount) or 1
	info = info or {}
	if itemInfo['type'] == 'weapon' then
		info.serie = info.serie or tostring(QBCore.Shared.RandomInt(2) .. QBCore.Shared.RandomStr(3) .. QBCore.Shared.RandomInt(1) .. QBCore.Shared.RandomStr(2) .. QBCore.Shared.RandomInt(3) .. QBCore.Shared.RandomStr(4))
	end
	slot = tonumber(slot) or GetFirstSlotByItem(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]), item, info)
 	if (totalWeight + (itemInfo['weight'] * amount)) <= Config.MaxInventoryWeight then
		if slot then
			local queries = {}
			for i = 1, amount, 1 do
				queries[#queries+1] = {query = 'INSERT INTO user_inventory2 (item_name, owner, information, slot, creationDate, quality) VALUES (?, ?, ?,  ?, ?, ?)', values = {itemInfo['name'], 'ply-'..Player.PlayerData.citizenid, json.encode(info), slot, os.time(), 100}}
			end
			local success = MySQL.transaction.await(queries)
			local item2 = MySQL.Sync.fetchAll('SELECT count(item_name) as amount, item_name, id, owner, information, slot, quality, MIN(creationDate) as creationDate FROM user_inventory2 WHERE owner = ? group by item_name, slot, owner', {'ply-'..Player.PlayerData.citizenid})
			inv['ply-'..Player.PlayerData.citizenid] = item2
			if Player.Offline then return success end
			TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'AddItem', 'green', '**' .. GetPlayerName(source) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. source .. ')** got item: [slot:' .. slot .. '], itemname: ' .. BuildInventory(inv['ply-'..Player.PlayerData.citizenid])[slot].name .. ', added amount: ' .. amount .. ', new total amount: ' .. BuildInventory(inv['ply-'..Player.PlayerData.citizenid])[slot].amount)
			return success
		else
			for i = 1, Config.MaxInventorySlots, 1 do
				if BuildInventory(inv['ply-'..Player.PlayerData.citizenid])[i] == nil then
					local queries = {}
					for j = 1, amount, 1 do
						queries[#queries+1] = {query = 'INSERT INTO user_inventory2 (item_name, owner, information, slot, creationDate, quality) VALUES (?, ?, ?, ?, ?, ?, ?)', values = {itemInfo['name'], 'ply-'..Player.PlayerData.citizenid, json.encode(info), i, os.time(), 100}}
					end
					local success = MySQL.transaction.await(queries)
					local item2 = MySQL.Sync.fetchAll('SELECT count(item_name) as amount, item_name, id, owner, information, slot, quality, MIN(creationDate) as creationDate FROM user_inventory2 WHERE owner = ? group by item_name, slot, owner', {'ply-'..Player.PlayerData.citizenid})
					inv['ply-'..Player.PlayerData.citizenid] = item2
					if Player.Offline then return success end
					TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'AddItem', 'green', '**' .. GetPlayerName(source) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. source .. ')** got item: [slot:' .. i .. '], itemname: ' .. BuildInventory(inv['ply-'..Player.PlayerData.citizenid])[i].name .. ', added amount: ' .. amount .. ', new total amount: ' .. BuildInventory(inv['ply-'..Player.PlayerData.citizenid])[i].amount)
					return success
				end
			end
		end
	elseif not Player.Offline then
		QBCore.Functions.Notify(source, "Inventory too full", 'error')
	end
	return false
end

exports("AddItem", AddItem)

---Remove an item from the inventory of the player

local function RemoveItem(source, item, amount, slot)
	local Player = QBCore.Functions.GetPlayer(source)
	if not Player then return false end
	amount = tonumber(amount) or 1
	slot = tonumber(slot)
	if slot then
		MySQL.query.await('DELETE FROM user_inventory2 WHERE owner = ? AND slot = ? LIMIT ?' , {'ply-'..Player.PlayerData.citizenid, slot, amount})
		local item = MySQL.Sync.fetchAll('SELECT count(item_name) as amount, item_name, id, owner, information, slot, quality, MIN(creationDate) as creationDate FROM user_inventory2 WHERE owner = ? group by item_name, slot, owner', {'ply-'..Player.PlayerData.citizenid})
		inv['ply-'..Player.PlayerData.citizenid] = item
		if Player.Offline then return true end
		TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'RemoveItem', 'red', '**' .. GetPlayerName(source) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. source .. ')** lost item: [slot:' .. slot .. '], itemname: ' .. item .. ', removed amount: ' .. amount .. ', new total amount: ' .. BuildInventory(inv['ply-'..Player.PlayerData.citizenid])[slot].amount)
		return true
	else
		local slots, amountHave = GetSlotsByItem(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]), item)
		if not slots then return false end
		if amount < amountHave then return false end
		for _, _slot in pairs(slots) do
			if BuildInventory(inv['ply-'..Player.PlayerData.citizenid])[_slot].amount >= amount then
				MySQL.query.await('DELETE FROM user_inventory2 WHERE owner = ? AND slot = ? LIMIT ?' , {'ply-'..Player.PlayerData.citizenid, _slot, amount})
				inv['ply-'..Player.PlayerData.citizenid] = item
				if Player.Offline then return true end
				TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'RemoveItem', 'red', '**' .. GetPlayerName(source) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. source .. ')** lost item: [slot:' .. _slot .. '], itemname: ' .. item .. ', removed amount: ' .. amount .. ', new total amount: ' .. BuildInventory(inv['ply-'..Player.PlayerData.citizenid])[_slot].amount)
				return true
			else
				MySQL.query.await('DELETE FROM user_inventory2 WHERE owner = ? AND slot = ? LIMIT ?' , {'ply-'..Player.PlayerData.citizenid, _slot, BuildInventory(inv['ply-'..Player.PlayerData.citizenid])[_slot].amount})
				amount -= BuildInventory(inv['ply-'..Player.PlayerData.citizenid])[_slot].amount
			end
		end
	end
	return false
end

exports("RemoveItem", RemoveItem)

---Get the item with the slot

local function GetItemBySlot(name, slot)
	slot = tonumber(slot)
	return BuildInventory(inv[name])[slot]
end

exports("GetItemBySlot", GetItemBySlot)

---Get the item from the inventory of the player with the provided source by the name of the item

local function GetItemByName(source, item)
	local Player = QBCore.Functions.GetPlayer(source)
	item = tostring(item):lower()
	local slot = GetFirstSlotByItem(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]), item)
	return BuildInventory(inv['ply-'..Player.PlayerData.citizenid])[slot]
end

exports("GetItemByName", GetItemByName)

---Get the item from the inventory of the player with the provided source by the name of the item in an array for all slots that the item is in

local function GetItemsByName(source, item)
	local Player = QBCore.Functions.GetPlayer(source)
	item = tostring(item):lower()
	local items = {}
	local slots = GetSlotsByItem(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]), item)
	for _, slot in pairs(slots) do
		if slot then
			items[#items+1] = BuildInventory(inv['ply-'..Player.PlayerData.citizenid])[slot]
		end
	end
	return items
end

exports("GetItemsByName", GetItemsByName)

local function ClearInventory(source, filterItems)
	local Player = QBCore.Functions.GetPlayer(source)
	if filterItems then
		local filterItemsType = type(filterItems)
		if filterItemsType == "string" then
			MySQL.query.await('UPDATE user_inventory2 SET owner = ? WHERE owner = ? AND item_name = ?' , {'saveply-'..Player.PlayerData.citizenid, 'ply-'..Player.PlayerData.citizenid, filterItems})
		elseif filterItemsType == "table" and table.type(filterItems) == "array" then
			local update_data = {}
			local query = "UPDATE user_inventory2 SET owner = ? WHERE owner = ? AND item_name = ?"
			for i = 1, #filterItems do
				update_data[#update_data + 1] = {query = query, values = {'saveply-'..Player.PlayerData.citizenid, 'ply-'..Player.PlayerData.citizenid, filterItems[i]}}
			end
			MySQL.transaction(update_data, function(result2)
				if result2 then
					print("Save Inventory")
				end
			end)
		end
	else
		MySQL.query.await('DELETE FROM user_inventory2 WHERE owner = ?' , {'ply-'..Player.PlayerData.citizenid})
	end
	MySQL.query.await('UPDATE user_inventory2 SET owner = ? WHERE owner = ?' , {'ply-'..Player.PlayerData.citizenid, 'saveply-'..Player.PlayerData.citizenid})
	inv['ply-'..Player.PlayerData.citizenid] = MySQL.Sync.fetchAll('SELECT count(item_name) as amount, item_name, id, owner, information, slot, quality, MIN(creationDate) as creationDate FROM user_inventory2 WHERE owner = ? group by item_name, slot, name', {'ply-'..Player.PlayerData.citizenid})
	if Player.Offline then return end
	TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'ClearInventory', 'red', '**' .. GetPlayerName(source) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. source .. ')** inventory cleared')
end

exports("ClearInventory", ClearInventory)

---Checks if you have an item or not
local function HasItem(source, items, amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    local isTable = type(items) == 'table'
    local isArray = isTable and table.type(items) == 'array' or false
    local totalItems = #items
    local count = 0
    local kvIndex = 2
    if isTable and not isArray then
        totalItems = 0
        for _ in pairs(items) do totalItems += 1 end
        kvIndex = 1
    end
    if isTable then
        for k, v in pairs(items) do
            local itemKV = {k, v}
            local item = GetItemByName(source, itemKV[kvIndex])
            if item and ((amount and item.amount >= amount) or (not isArray and item.amount >= v) or (not amount and isArray)) then
                count += 1
            end
        end
        if count == totalItems then
            return true
        end
    else -- Single item as string
        local item = GetItemByName(source, items)
        if item and (not amount or (item and amount and item.amount >= amount)) then
            return true
        end
    end
    return false
end

exports("HasItem", HasItem)

---Create a usable item with a callback on use
---@param itemName string The name of the item to make usable
---@param data any
local function CreateUsableItem(itemName, data)
	QBCore.Functions.CreateUseableItem(itemName, data)
end

exports("CreateUsableItem", CreateUsableItem)

---Get the usable item data for the specified item
---@param itemName string The item to get the data for
---@return any usable_item
local function GetUsableItem(itemName)
	return QBCore.Functions.CanUseItem(itemName)
end

exports("GetUsableItem", GetUsableItem)

---Use an item from the QBCore.UsableItems table if a callback is present
---@param itemName string The name of the item to use
---@param ... any Arguments for the callback, this will be sent to the callback and can be used to get certain values
local function UseItem(itemName, ...)
	local itemData = GetUsableItem(itemName)
	local callback = type(itemData) == 'table' and (rawget(itemData, '__cfx_functionReference') and itemData or itemData.cb or itemData.callback) or type(itemData) == 'function' and itemData
	if not callback then return end
	callback(...)
end

exports("UseItem", UseItem)

local function recipeContains(recipe, fromItem)
	for _, v in pairs(recipe.accept) do
		if v == fromItem.name then
			return true
		end
	end

	return false
end

local function hasCraftItems(source, CostItems, amount)
	for k, v in pairs(CostItems) do
		local item = GetItemByName(source, k)

		if not item then return false end

		if item.amount < (v * amount) then return false end
	end
	return true
end

-- Shop Items
local function SetupShopItems(shopItems)
	local items = {}
	if shopItems and next(shopItems) then
		for _, item in pairs(shopItems) do
			local itemInfo = QBCore.Shared.Items[item.name:lower()]
			if itemInfo then
				items[item.slot] = {
					name = itemInfo["name"],
					amount = tonumber(item.amount),
					info = item.info or "",
					label = itemInfo["label"],
					description = itemInfo["description"] or "",
					weight = itemInfo["weight"],
					type = itemInfo["type"],
					unique = itemInfo["unique"],
					useable = itemInfo["useable"],
					price = item.price,
					image = itemInfo["image"],
					slot = item.slot,
				}
			end
		end
	end
	return items
end

local function CreateDropId()
	if Drops then
		local id = math.random(10000, 99999)
		local dropid = id
		while Drops[dropid] do
			id = math.random(10000, 99999)
			dropid = id
		end
		return dropid
	else
		local id = math.random(10000, 99999)
		local dropid = id
		return dropid
	end
end

-- Events

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
	QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "AddItem", function(item, amount, slot, info)
		return AddItem(Player.PlayerData.source, item, amount, slot, info)
	end)

	QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "RemoveItem", function(item, amount, slot)
		return RemoveItem(Player.PlayerData.source, item, amount, slot)
	end)

	QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "GetItemBySlot", function(slot)
		local Player = QBCore.Functions.GetPlayer(Player.PlayerData.source)
		return GetItemBySlot('ply-'..Player.PlayerData.citizenid, slot)
	end)

	QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "GetItemByName", function(item)
		return GetItemByName(Player.PlayerData.source, item)
	end)

	QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "GetItemsByName", function(item)
		return GetItemsByName(Player.PlayerData.source, item)
	end)

	QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "ClearInventory", function(filterItems)
		ClearInventory(Player.PlayerData.source, filterItems)
	end)

	QBCore.Functions.AddPlayerMethod(Player.PlayerData.source, "SetInventory", function(items)
		SetInventory(Player.PlayerData.source, items)
	end)
end)

AddEventHandler('onResourceStart', function(resourceName)
	if resourceName ~= GetCurrentResourceName() then return end
	local Players = QBCore.Functions.GetQBPlayers()
	for k in pairs(Players) do
		QBCore.Functions.AddPlayerMethod(k, "AddItem", function(item, amount, slot, info)
			return AddItem(k, item, amount, slot, info)
		end)

		QBCore.Functions.AddPlayerMethod(k, "RemoveItem", function(item, amount, slot)
			return RemoveItem(k, item, amount, slot)
		end)

		QBCore.Functions.AddPlayerMethod(k, "GetItemBySlot", function(slot)
			local Player = QBCore.Functions.GetPlayer(k)
			return GetItemBySlot('ply-'..Player.PlayerData.citizenid, slot)
		end)

		QBCore.Functions.AddPlayerMethod(k, "GetItemByName", function(item)
			return GetItemByName(k, item)
		end)

		QBCore.Functions.AddPlayerMethod(k, "GetItemsByName", function(item)
			return GetItemsByName(k, item)
		end)

		QBCore.Functions.AddPlayerMethod(k, "ClearInventory", function(filterItems)
			ClearInventory(k, filterItems)
		end)

		QBCore.Functions.AddPlayerMethod(k, "SetInventory", function(items)
			SetInventory(k, items)
		end)
	end
end)

RegisterNetEvent('QBCore:Server:UpdateObject', function()
    if source ~= '' then return end -- Safety check if the event was not called from the server.
    QBCore = exports['qb-core']:GetCoreObject()
end)

RegisterNetEvent('inventory:server:combineItem', function(item, fromItem, toItem)
	local src = source

	-- Check that inputs are not nil
	-- Most commonly when abusing this exploit, this values are left as
	if fromItem == nil  then return end
	if toItem == nil then return end

	-- Check that they have the items
	fromItem = GetItemByName(src, fromItem)
	toItem = GetItemByName(src, toItem)

	if fromItem == nil  then return end
	if toItem == nil then return end

	-- Check the recipe is valid
	local recipe = QBCore.Shared.Items[toItem.name].combinable

	if recipe and recipe.reward ~= item then return end
	if not recipeContains(recipe, fromItem) then return end

	TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[item], 'add')
	AddItem(src, item, 1)
	RemoveItem(src, fromItem.name, 1)
	RemoveItem(src, toItem.name, 1)
end)

RegisterNetEvent('inventory:server:CraftItems', function(itemName, itemCosts, amount, toSlot, points)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)

	amount = tonumber(amount)

	if not itemName or not itemCosts then return end

	for k, v in pairs(itemCosts) do
		RemoveItem(src, k, (v*amount))
	end
	AddItem(src, itemName, amount, toSlot)
	Player.Functions.SetMetaData("craftingrep", Player.PlayerData.metadata["craftingrep"] + (points * amount))
	TriggerClientEvent("inventory:client:UpdatePlayerInventory", src, false)
end)

RegisterNetEvent('inventory:server:CraftAttachment', function(itemName, itemCosts, amount, toSlot, points)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	amount = tonumber(amount)
	if not itemName or not itemCosts then return end
	for k, v in pairs(itemCosts) do
		RemoveItem(src, k, (v*amount))
	end
	AddItem(src, itemName, amount, toSlot)
	Player.Functions.SetMetaData("attachmentcraftingrep", Player.PlayerData.metadata["attachmentcraftingrep"] + (points * amount))
	TriggerClientEvent("inventory:client:UpdatePlayerInventory", src, false)
end)

RegisterNetEvent('inventory:server:SetIsOpenState', function(IsOpen, type, id)
	if IsOpen then return end
	if type == "stash" then
		Stashes[id].isOpen = false
	elseif type == "trunk" then
		Trunks[id].isOpen = false
	elseif type == "glovebox" then
		Gloveboxes[id].isOpen = false
	elseif type == "drop" then
		if id ~= 0 then
			Drops[id].isOpen = false
		end
	end
end)

RegisterNetEvent('inventory:server:OpenInventory', function(name, id, other)
	local src = source
	local ply = Player(src)
	local Player = QBCore.Functions.GetPlayer(src)
	if not ply.state.inv_busy then
		if name and id then
			local secondInv = {}
			if name == "stash" then
				if Stashes[id] then
					if Stashes[id].isOpen then
						local Target = QBCore.Functions.GetPlayer(Stashes[id].isOpen)
						if Target then
							TriggerClientEvent('inventory:client:CheckOpenState', Stashes[id].isOpen, name, id, Stashes[id].label)
						else
							Stashes[id].isOpen = false
						end
					end
				end
				local maxweight = 1000000
				local slots = 50
				if other then
					maxweight = other.maxweight or 1000000
					slots = other.slots or 50
				end
				secondInv.name = "stash-"..id
				secondInv.label = "Stash-"..id
				secondInv.maxweight = maxweight
				secondInv.inventory = {}
				secondInv.slots = slots
				if Stashes[id] and Stashes[id].isOpen then
					secondInv.name = "none-inv"
					secondInv.label = "Stash-None"
					secondInv.maxweight = 1000000
					secondInv.inventory = {}
					secondInv.slots = 0
				else
					local stashItems = BuildInventory(inv['Stash-'..id])
					secondInv.inventory = stashItems
					Stashes[id] = {}
					Stashes[id].items = stashItems
					Stashes[id].isOpen = src
					Stashes[id].label = secondInv.label
					Stashes[id].name = secondInv.name
					Stashes[id].slots = secondInv.slots
					Stashes[id].maxweight = secondInv.maxweight
				end
			elseif name == "trunk" then
				if Trunks[id] then
					if Trunks[id].isOpen then
						local Target = QBCore.Functions.GetPlayer(Trunks[id].isOpen)
						if Target then
							TriggerClientEvent('inventory:client:CheckOpenState', Trunks[id].isOpen, name, id, Trunks[id].label)
						else
							Trunks[id].isOpen = false
						end
					end
				end
				secondInv.name = "trunk-"..id
				secondInv.label = "Trunk-"..id
				secondInv.maxweight = other.maxweight or 60000
				secondInv.inventory = {}
				secondInv.slots = other.slots or 50
				if (Trunks[id] and Trunks[id].isOpen) or (QBCore.Shared.SplitStr(id, "PLZI")[2] and Player.PlayerData.job.name ~= "police") then
					secondInv.name = "none-inv"
					secondInv.label = "Trunk-None"
					secondInv.maxweight = other.maxweight or 60000
					secondInv.inventory = {}
					secondInv.slots = 0
				else
					if id then
						local ownedItems = BuildInventory(inv['Trunk-'..id])
						secondInv.inventory = ownedItems
						Trunks[id] = {}
						Trunks[id].isOpen = src
						Trunks[id].name = secondInv.name
						Trunks[id].label = secondInv.label
						Trunks[id].slots = secondInv.slots
						Trunks[id].maxweight = secondInv.maxweight
					end
				end
			elseif name == "glovebox" then
				if Gloveboxes[id] then
					if Gloveboxes[id].isOpen then
						local Target = QBCore.Functions.GetPlayer(Gloveboxes[id].isOpen)
						if Target then
							TriggerClientEvent('inventory:client:CheckOpenState', Gloveboxes[id].isOpen, name, id, Gloveboxes[id].label)
						else
							Gloveboxes[id].isOpen = false
						end
					end
				end
				secondInv.name = "glovebox-"..id
				secondInv.label = "Glovebox-"..id
				secondInv.maxweight = 10000
				secondInv.inventory = {}
				secondInv.slots = 5
				if Gloveboxes[id] and Gloveboxes[id].isOpen then
					secondInv.name = "none-inv"
					secondInv.label = "Glovebox-None"
					secondInv.maxweight = 10000
					secondInv.inventory = {}
					secondInv.slots = 0
				else
					local ownedItems = BuildInventory(inv['GloveBox-'..id])
					secondInv.inventory = ownedItems
					Gloveboxes[id] = {}
					Gloveboxes[id].items = ownedItems
					Gloveboxes[id].isOpen = src
					Gloveboxes[id].label = secondInv.label
					Gloveboxes[id].name = secondInv.name
					Gloveboxes[id].slots = secondInv.slots
					Gloveboxes[id].maxweight = secondInv.maxweight
				end
			elseif name == "shop" then
				secondInv.name = "itemshop-"..id
				secondInv.label = other.label
				secondInv.maxweight = 900000
				secondInv.inventory = SetupShopItems(other.items)
				ShopItems[id] = {}
				ShopItems[id].items = other.items
				secondInv.slots = #other.items
			elseif name == "traphouse" then
				secondInv.name = "traphouse-"..id
				secondInv.label = other.label
				secondInv.maxweight = 900000
				secondInv.inventory = other.items
				secondInv.slots = other.slots
			elseif name == "crafting" then
				secondInv.name = "crafting"
				secondInv.label = other.label
				secondInv.maxweight = 900000
				secondInv.inventory = other.items
				secondInv.slots = #other.items
			elseif name == "attachment_crafting" then
				secondInv.name = "attachment_crafting"
				secondInv.label = other.label
				secondInv.maxweight = 900000
				secondInv.inventory = other.items
				secondInv.slots = #other.items
			elseif name == "otherplayer" then
				local OtherPlayer = QBCore.Functions.GetPlayer(tonumber(id))
				if OtherPlayer then
					secondInv.name = "otherplayer-"..id
					secondInv.label = "Player-"..id
					secondInv.maxweight = Config.MaxInventoryWeight
					secondInv.inventory = BuildInventory(inv['ply-'..OtherPlayer.PlayerData.citizenid])
					if Player.PlayerData.job.name == "police" and Player.PlayerData.job.onduty then
						secondInv.slots = Config.MaxInventorySlots
					else
						secondInv.slots = Config.MaxInventorySlots - 1
					end
					Wait(250)
				end
			else
				if Drops[id] then
					if Drops[id].isOpen then
						local Target = QBCore.Functions.GetPlayer(Drops[id].isOpen)
						if Target then
							TriggerClientEvent('inventory:client:CheckOpenState', Drops[id].isOpen, name, id, Drops[id].label)
						else
							Drops[id].isOpen = false
						end
					end
				end
				if Drops[id] and not Drops[id].isOpen then
					secondInv.coords = Drops[id].coords
					secondInv.name = id
					secondInv.label = "Dropped-"..tostring(id)
					secondInv.maxweight = 100000
					secondInv.inventory = BuildInventory(inv['Drop-'..id])
					secondInv.slots = 30
					Drops[id].isOpen = src
					Drops[id].name = secondInv.name
					Drops[id].label = secondInv.label
					Drops[id].createdTime = os.time()
					Drops[id].slots = secondInv.slots
					Drops[id].maxweight = secondInv.maxweight
				else
					secondInv.name = "none-inv"
					secondInv.label = "Dropped-None"
					secondInv.maxweight = 100000
					secondInv.inventory = {}
					secondInv.slots = 0
				end
			end
			TriggerClientEvent("qb-inventory:client:closeinv", id)
			TriggerClientEvent("inventory:client:OpenInventory", src, {}, BuildInventory(inv['ply-'..Player.PlayerData.citizenid]), secondInv)
		else
			TriggerClientEvent("inventory:client:OpenInventory", src, {}, BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
		end
	else
		TriggerClientEvent('QBCore:Notify', src, 'Not Accessible', 'error')
	end
end)

RegisterNetEvent('inventory:server:UseItemSlot', function(slot)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	local itemData = Player.Functions.GetItemBySlot(slot)
	if itemData then
	local itemInfo = QBCore.Shared.Items[itemData.name]
	if itemData.type == "weapon" then
			if itemData.info.quality then
				if itemData.info.quality > 0 then
					TriggerClientEvent("inventory:client:UseWeapon", src, itemData, true)
				else
					TriggerClientEvent("inventory:client:UseWeapon", src, itemData, false)
				end
			else
				TriggerClientEvent("inventory:client:UseWeapon", src, itemData, true)
			end
		TriggerClientEvent('inventory:client:ItemBox', src, itemInfo, "use")
	elseif itemData.useable then
			if itemData.info.quality then
				if itemData.info.quality > 0 then
		UseItem(itemData.name, src, itemData)
		TriggerClientEvent('inventory:client:ItemBox', src, itemInfo, "use")
				else
					if itemInfo['delete'] and RemoveItem(src,itemData.name,1,slot) then
						TriggerClientEvent('inventory:client:ItemBox',src, itemInfo, "remove")
					else
						TriggerClientEvent("QBCore:Notify", src, "You can't use this item", "error")
					end
				end
			else
				UseItem(itemData.name, src, itemData)
				TriggerClientEvent('inventory:client:ItemBox', src, itemInfo, "use")
			end
		end
	end
end)

RegisterNetEvent('inventory:server:UseItem', function(inventory, item)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	if inventory == "player" or inventory == "hotbar" then
		local itemData = Player.Functions.GetItemBySlot(item.slot)
		if itemData then
	local itemInfo = QBCore.Shared.Items[itemData.name]
			if itemData.type ~= "weapon" then
				if itemData.info.quality then
					if itemData.info.quality <= 0 then
						if itemInfo['delete'] and RemoveItem(src,itemData.name,1,item.slot) then
							TriggerClientEvent("QBCore:Notify", src, "You can't use this item", "error")
							TriggerClientEvent('inventory:client:ItemBox',src, itemInfo, "remove")
							return
	else
							TriggerClientEvent("QBCore:Notify", src, "You can't use this item", "error")
							return
						end
					end
				end
			end
		UseItem(itemData.name, src, itemData)
		TriggerClientEvent('inventory:client:ItemBox', src, itemInfo, "use")
	end
	end
end)

QBCore.Functions.CreateCallback('inventory:server:SetInventoryData', function(source, cb, data)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	local fromInventory = data.fromInventory
	local toInventory = data.toInventory
	local fromAmount = tonumber(data.fromAmount)
	local toAmount = tonumber(data.toAmount)
	local fromSlot = tonumber(data.fromSlot)
	local toSlot = tonumber(data.toSlot)
	local other = {}
	local inventory = BuildInventory(inv['ply-'..Player.PlayerData.citizenid])
	if (fromInventory == "player" or fromInventory == "hotbar") and (QBCore.Shared.SplitStr(toInventory, "-")[1] == "itemshop" or toInventory == "crafting") then
		inventory = ConvertQualityInv(inventory)
		cb(inventory)
	end
	if fromInventory == "player" or fromInventory == "hotbar" then
		local fromItemData = GetItemBySlot('ply-'..Player.PlayerData.citizenid, fromSlot)
		fromAmount = tonumber(fromAmount) or fromItemData.amount
		if fromItemData and fromItemData.amount >= fromAmount then
			if toInventory == "player" or toInventory == "hotbar" then
				TriggerClientEvent("inventory:client:CheckWeapon", src, fromItemData.name)
				local toItemData = GetItemBySlot('ply-'..Player.PlayerData.citizenid, toSlot)
				if toItemData ~= nil then
					local toAmount = tonumber(toAmount) ~= nil and tonumber(toAmount) or toItemData.amount
                    if toItemData.amount >= toAmount then
						if toItemData.name ~= fromItemData.name then
							ChangeSlot(fromItemData.name,'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, fromAmount)
							ChangeSlot(toItemData.name, 'ply-'..Player.PlayerData.citizenid,  toSlot, fromSlot, toItemData.amount)
							if Player.Offline then return true end
							TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
						else
							local success = compareArrays(toItemData.info, fromItemData.info)
							if success then
								ChangeSlot(fromItemData.name, 'ply-'..Player.PlayerData.citizenid,  fromSlot, toSlot, fromAmount)
								if Player.Offline then return true end
								TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
							end
						end
					else
						TriggerEvent("qb-log:server:CreateLog", "anticheat", "Dupe log", "red", "**".. GetPlayerName(src) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | *"..src.."*) swapped item; name: **"..toItemData.name.."**, amount: **" .. toAmount .. "** with name: **" .. fromItemData.name .. "**, amount: **" .. fromAmount.. "**")
					end
				else
					ChangeSlot(fromItemData.name, 'ply-'..Player.PlayerData.citizenid,  fromSlot, toSlot, fromAmount)
					if Player.Offline then return true end
					TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
				end
				inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
				cb(inventory)
			elseif QBCore.Shared.SplitStr(toInventory, "-")[1] == "otherplayer" then
				TriggerClientEvent("inventory:client:CheckWeapon", src, fromItemData.name)
				local playerId = tonumber(QBCore.Shared.SplitStr(toInventory, "-")[2])
				other.name = "otherplayer-"..playerId
				other.label = "Player-"..playerId
				other.maxweight = Config.MaxInventoryWeight
				local otherPlayer = QBCore.Functions.GetPlayer(playerId)
				other.inventory = BuildInventory(inv['ply-'..otherPlayer.PlayerData.citizenid])
				local toItemData = GetItemBySlot('ply-'..otherPlayer.PlayerData.citizenid, toSlot)
				if Player.PlayerData.job.name == "police" and Player.PlayerData.job.onduty then
					other.slots = Config.MaxInventorySlots
				else
					other.slots = Config.MaxInventorySlots - 1
				end
				if toItemData ~= nil then
					if toItemData.name ~= fromItemData.name then
						ChangeInv(toItemData.name, 'ply-'..otherPlayer.PlayerData.citizenid, toSlot, fromSlot, 'ply-'..Player.PlayerData.citizenid, toItemData.amount)
						ChangeInv(fromItemData.name, 'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, 'ply-'..otherPlayer.PlayerData.citizenid, fromAmount)
					else
						local success = compareArrays(toItemData.info, fromItemData.info)
						if success then
							ChangeInv(fromItemData.name, 'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, 'ply-'..otherPlayer.PlayerData.citizenid, fromAmount)
							if Player.Offline then return true end
							TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
						end
					end
				else
					ChangeInv(fromItemData.name, 'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, 'ply-'..otherPlayer.PlayerData.citizenid, fromAmount)
				end
				other.inventory = ConvertQualityInv(BuildInventory(inv['ply-'..otherPlayer.PlayerData.citizenid]))
				inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
				cb(inventory, other)
			elseif QBCore.Shared.SplitStr(toInventory, "-")[1] == "trunk" then
				TriggerClientEvent("inventory:client:CheckWeapon", src, fromItemData.name)
				local plate = QBCore.Shared.SplitStr(toInventory, "-")[2]
				other.inventory = BuildInventory(inv['Trunk-'..plate])
				other.name = Trunks[plate].name
				other.label =Trunks[plate].label
				other.slots =Trunks[plate].slots
				other.maxweight = Trunks[plate].maxweight
				local toItemData = GetItemBySlot("Trunk-"..plate, toSlot)
				if toItemData ~= nil then
					if toItemData.name ~= fromItemData.name then
						ChangeInv(toItemData.name, 'Trunk-'..plate, toSlot, fromSlot, 'ply-'..Player.PlayerData.citizenid, toItemData.amount)
						ChangeInv(fromItemData.name, 'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, 'Trunk-'..plate, fromAmount)
					else
						local success = compareArrays(toItemData.info, fromItemData.info)
						if success then
							ChangeInv(fromItemData.name, 'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, 'Trunk-'..plate, fromAmount)
							if Player.Offline then return true end
							TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
						end
					end
				else
					ChangeInv(fromItemData.name, 'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, 'Trunk-'..plate, fromAmount)
				end
				other.inventory = ConvertQualityInv(BuildInventory(inv['Trunk-'..plate]))
				inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
				cb(inventory, other)
			elseif QBCore.Shared.SplitStr(toInventory, "-")[1] == "glovebox" then
				TriggerClientEvent("inventory:client:CheckWeapon", src, fromItemData.name)
				local plate = QBCore.Shared.SplitStr(toInventory, "-")[2]
				other.inventory = BuildInventory(inv['GloveBox-'..plate])
				other.name = Gloveboxes[plate].name
				other.label = Gloveboxes[plate].label
				other.slots = Gloveboxes[plate].slots
				other.maxweight = Gloveboxes[plate].maxweight
				local toItemData = GetItemBySlot("GloveBox-"..plate, toSlot)
				if toItemData ~= nil then
					if toItemData.name ~= fromItemData.name then
						ChangeInv(toItemData.name, 'GloveBox-'..plate, toSlot, fromSlot, 'ply-'..Player.PlayerData.citizenid, toItemData.amount)
						ChangeInv(fromItemData.name, 'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, 'GloveBox-'..plate, fromAmount)
					else
						local success = compareArrays(toItemData.info, fromItemData.info)
						if success then
							ChangeInv(fromItemData.name, 'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, 'GloveBox-'..plate, fromAmount)
							if Player.Offline then return true end
							TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
						end
					end
				else
					ChangeInv(fromItemData.name, 'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, 'GloveBox-'..plate, fromAmount)
				end
				other.inventory = ConvertQualityInv(BuildInventory(inv['GloveBox-'..plate]))
				inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
				cb(inventory, other)
			elseif QBCore.Shared.SplitStr(toInventory, "-")[1] == "stash" then
				TriggerClientEvent("inventory:client:CheckWeapon", src, fromItemData.name)
				local id = QBCore.Shared.SplitStr(toInventory, "-")[2]
				local toItemData = GetItemBySlot("Stash-"..id, toSlot)
				other.inventory = BuildInventory(inv['Stash-'..id])
				other.name = Stashes[id].name
				other.label = Stashes[id].label
				other.slots = Stashes[id].slots
				other.maxweight = Stashes[id].maxweight
				if toItemData ~= nil then
					if toItemData.name ~= fromItemData.name then
						ChangeInv(toItemData.name, 'Stash-'..id, toSlot, fromSlot, 'ply-'..Player.PlayerData.citizenid, toItemData.amount)
						ChangeInv(fromItemData.name, 'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, 'Stash-'..id, fromAmount)
					else
						local success = compareArrays(toItemData.info, fromItemData.info)
						if success then
							ChangeInv(fromItemData.name, 'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, 'Stash-'..id, fromAmount)
							if Player.Offline then return true end
							TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
						end
					end
				else
					ChangeInv(fromItemData.name, 'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, 'Stash-'..id, fromAmount)
				end
				other.inventory = ConvertQualityInv(BuildInventory(inv['Stash-'..id]))
				inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
				cb(inventory, other)
			else
				TriggerClientEvent("inventory:client:CheckWeapon", src, fromItemData.name)
				local create = false
				local id = toInventory
				if toInventory == nil or tonumber(toInventory) == 0 or toInventory == 0 then
					local coords = GetEntityCoords(GetPlayerPed(source))
					local dropId = tostring(CreateDropId())
					Drops[dropId] = {}
					Drops[dropId].coords = coords
					Drops[dropId].createdTime = os.time()
					create = true
					id = dropId
					TriggerClientEvent("inventory:client:AddDropItem", -1, dropId, source, coords)
				end
				other.inventory = BuildInventory(inv['Drop-'..id])
				other.name = Drops[id].name
				other.label = Drops[id].label
				other.slots = Drops[id].slots
				other.maxweight = Drops[id].maxweight
				local toItemData = GetItemBySlot("Drop-"..id, toSlot)
				if toItemData ~= nil then
					if toItemData.name ~= fromItemData.name then
						ChangeInv(toItemData.name, 'Drop-'..id, toSlot, fromSlot, 'ply-'..Player.PlayerData.citizenid, toItemData.amount)
						ChangeInv(fromItemData.name, 'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, 'Drop-'..id, fromAmount)
					else
						if toItemData.info ~= fromItemData.info then
							if not create then
								local inventory = BuildInventory(inv['ply-'..Player.PlayerData.citizenid])
								cb(inventory)
							end
						else
							ChangeInv(fromItemData.name, 'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, 'Drop-'..id, fromAmount)
							if Player.Offline then return true end
							TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
						end
					end
				else
					ChangeInv(fromItemData.name, 'ply-'..Player.PlayerData.citizenid, fromSlot, toSlot, 'Drop-'..id, fromAmount)
				end
				if create then
					TriggerClientEvent("inventory:client:DropItemAnim", source)
					cb(false)
				end
				other.inventory = ConvertQualityInv(BuildInventory(inv['Drop-'..id]))
				inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
				cb(inventory, other)
			end
		else
			TriggerClientEvent("QBCore:Notify", src, "You don't have this item!", "error")
		end
	elseif QBCore.Shared.SplitStr(fromInventory, "-")[1] == "otherplayer" then
		local playerId = tonumber(QBCore.Shared.SplitStr(fromInventory, "-")[2])
		local otherPlayer = QBCore.Functions.GetPlayer(playerId)
		local fromItemData = GetItemBySlot('ply-'..otherPlayer.PlayerData.citizenid, fromSlot)
		other.name = "otherplayer-"..playerId
		other.label = "Player-"..playerId
		other.maxweight = Config.MaxInventoryWeight
		other.inventory = BuildInventory(inv['ply-'..otherPlayer.PlayerData.citizenid])
		if Player.PlayerData.job.name == "police" and Player.PlayerData.job.onduty then
			other.slots = Config.MaxInventorySlots
		else
			other.slots = Config.MaxInventorySlots - 1
		end
		TriggerClientEvent("inventory:client:CheckWeapon", otherPlayer.PlayerData.source, fromItemData.name)
		fromAmount = tonumber(fromAmount) or fromItemData.amount
		if fromItemData and fromItemData.amount >= fromAmount then
			local toItemData = GetItemBySlot('ply-'..Player.PlayerData.citizenid, toSlot)
			if toItemData ~= nil then
				if toItemData.name ~= fromItemData.name then
					ChangeInv(toItemData.name, 'ply-'..Player.PlayerData.citizenid, toSlot, fromSlot, 'ply-'..otherPlayer.PlayerData.citizenid, toItemData.amount)
					ChangeInv(fromItemData.name, 'ply-'..otherPlayer.PlayerData.citizenid, fromSlot, toSlot, 'ply-'..Player.PlayerData.citizenid, fromAmount)
				else
					local success = compareArrays(toItemData.info, fromItemData.info)
						if success then
						ChangeInv(fromItemData.name, 'ply-'..otherPlayer.PlayerData.citizenid, fromSlot, toSlot, 'ply-'..Player.PlayerData.citizenid, fromAmount)
						if Player.Offline then return true end
						TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
					end
				end
			else
				ChangeInv(fromItemData.name, 'ply-'..otherPlayer.PlayerData.citizenid, fromSlot, toSlot, 'ply-'..Player.PlayerData.citizenid, fromAmount)
			end
			other.inventory = ConvertQualityInv(BuildInventory(inv['ply-'..otherPlayer.PlayerData.citizenid]))
			inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
			cb(inventory, other)
		else
			TriggerClientEvent("QBCore:Notify", src, "You don't have this item!", "error")
		end
	elseif QBCore.Shared.SplitStr(fromInventory, "-")[1] == "trunk" then
		local plate = QBCore.Shared.SplitStr(fromInventory, "-")[2]
		other.inventory = BuildInventory(inv['Trunk-'..plate])
		other.name = Trunks[plate].name
		other.label =Trunks[plate].label
		other.slots =Trunks[plate].slots
		other.maxweight = Trunks[plate].maxweight
		local fromItemData = GetItemBySlot("Trunk-"..plate, fromSlot)
		if fromItemData and fromItemData.amount >= fromAmount then
			if toInventory == "player" or toInventory == "hotbar" then
				local toItemData = GetItemBySlot('ply-'..Player.PlayerData.citizenid, toSlot)
				if toItemData ~= nil then
					if toItemData.name ~= fromItemData.name then
						ChangeInv(toItemData.name, 'ply-'..Player.PlayerData.citizenid, toSlot, fromSlot, 'Trunk-'..plate, toItemData.amount)
						ChangeInv(fromItemData.name, 'Trunk-'..plate, fromSlot, toSlot, 'ply-'..Player.PlayerData.citizenid, fromAmount)
					else
						local success = compareArrays(toItemData.info, fromItemData.info)
						if success then
							ChangeInv(fromItemData.name, 'Trunk-'..plate, fromSlot, toSlot, 'ply-'..Player.PlayerData.citizenid, fromAmount)
							if Player.Offline then return true end
							TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
						end
					end
				else
					ChangeInv(fromItemData.name, 'Trunk-'..plate, fromSlot, toSlot, 'ply-'..Player.PlayerData.citizenid, fromAmount)
				end
				other.inventory = ConvertQualityInv(BuildInventory(inv['Trunk-'..plate]))
				inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
				cb(inventory, other)
			else
				local toItemData = GetItemBySlot("Trunk-"..plate, toSlot)
				if toItemData ~= nil then
					if toItemData.name ~= fromItemData.name then
						ChangeInv(toItemData.name, "Trunk-"..plate, toSlot, fromSlot, 'Trunk-'..plate, toItemData.amount)
						ChangeInv(fromItemData.name, 'Trunk-'..plate, fromSlot, toSlot, "Trunk-"..plate, fromAmount)
					else
						local success = compareArrays(toItemData.info, fromItemData.info)
						if success then
							ChangeInv(fromItemData.name, 'Trunk-'..plate, fromSlot, toSlot, "Trunk-"..plate, fromAmount)
							if Player.Offline then return true end
							TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
						end
					end
				else
					ChangeInv(fromItemData.name, 'Trunk-'..plate, fromSlot, toSlot, "Trunk-"..plate, fromAmount)
				end
				other.inventory = ConvertQualityInv(BuildInventory(inv['Trunk-'..plate]))
				inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
				cb(inventory, other)
			end
		else
			TriggerClientEvent("QBCore:Notify", src, "You don't have this item!", "error")
		end
	elseif QBCore.Shared.SplitStr(fromInventory, "-")[1] == "glovebox" then
		local plate = QBCore.Shared.SplitStr(fromInventory, "-")[2]
		other.inventory = BuildInventory(inv['GloveBox-'..plate])
		other.name = Gloveboxes[plate].name
		other.label =Gloveboxes[plate].label
		other.slots =Gloveboxes[plate].slots
		other.maxweight = Gloveboxes[plate].maxweight
		local fromItemData = GetItemBySlot("GloveBox-"..plate, fromSlot)
		if fromItemData and fromItemData.amount >= fromAmount then
			if toInventory == "player" or toInventory == "hotbar" then
				local toItemData = GetItemBySlot('ply-'..Player.PlayerData.citizenid, toSlot)
				if toItemData ~= nil then
					if toItemData.name ~= fromItemData.name then
						ChangeInv(toItemData.name, 'ply-'..Player.PlayerData.citizenid, toSlot, fromSlot, 'GloveBox-'..plate, toItemData.amount)
						ChangeInv(fromItemData.name, 'GloveBox-'..plate, fromSlot, toSlot, 'ply-'..Player.PlayerData.citizenid, fromAmount)
					else
						local success = compareArrays(toItemData.info, fromItemData.info)
						if success then
							ChangeInv(fromItemData.name, 'GloveBox-'..plate, fromSlot, toSlot, 'ply-'..Player.PlayerData.citizenid, fromAmount)
							if Player.Offline then return true end
							TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
						end
					end
				else
					ChangeInv(fromItemData.name, 'GloveBox-'..plate, fromSlot, toSlot, 'ply-'..Player.PlayerData.citizenid, fromAmount)
				end
				other.inventory = ConvertQualityInv(BuildInventory(inv['GloveBox-'..plate]))
				inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
				cb(inventory, other)
			else
				local toItemData = GetItemBySlot("GloveBox-"..plate, toSlot)
				if toItemData ~= nil then
					if toItemData.name ~= fromItemData.name then
						ChangeInv(toItemData.name, "GloveBox-"..plate, toSlot, fromSlot, 'GloveBox-'..plate, toItemData.amount)
						ChangeInv(fromItemData.name, 'GloveBox-'..plate, fromSlot, toSlot, "GloveBox-"..plate, fromAmount)
					else
						local success = compareArrays(toItemData.info, fromItemData.info)
						if success then
							ChangeInv(fromItemData.name, 'GloveBox-'..plate, fromSlot, toSlot, "GloveBox-"..plate, fromAmount)
							if Player.Offline then return true end
							TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
						end
					end
				else
					ChangeInv(fromItemData.name, 'GloveBox-'..plate, fromSlot, toSlot, "GloveBox-"..plate, fromAmount)
				end
				other.inventory = ConvertQualityInv(BuildInventory(inv['GloveBox-'..plate]))
				inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
				cb(inventory, other)
			end
		else
			TriggerClientEvent("QBCore:Notify", src, "You don't have this item!", "error")
		end
	elseif QBCore.Shared.SplitStr(fromInventory, "-")[1] == "stash" then
		local id = QBCore.Shared.SplitStr(fromInventory, "-")[2]
		other.inventory = BuildInventory(inv['Stash-'..id])
		other.name = Stashes[id].name
		other.label =Stashes[id].label
		other.slots =Stashes[id].slots
		other.maxweight = Stashes[id].maxweight
		local fromItemData = GetItemBySlot("Stash-"..id, fromSlot)
		if fromItemData and fromItemData.amount >= fromAmount then
			if toInventory == "player" or toInventory == "hotbar" then
				local toItemData = GetItemBySlot('ply-'..Player.PlayerData.citizenid, toSlot)
				if toItemData ~= nil then
					if toItemData.name ~= fromItemData.name then
						ChangeInv(toItemData.name, 'ply-'..Player.PlayerData.citizenid, toSlot, fromSlot, 'Stash-'..id, toItemData.amount)
						ChangeInv(fromItemData.name, 'Stash-'..id, fromSlot, toSlot, 'ply-'..Player.PlayerData.citizenid, fromAmount)
					else
						local success = compareArrays(toItemData.info, fromItemData.info)
						if success then
							ChangeInv(fromItemData.name, 'Stash-'..id, fromSlot, toSlot, 'ply-'..Player.PlayerData.citizenid, fromAmount)
							if Player.Offline then return true end
							TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
						end
					end
				else
					ChangeInv(fromItemData.name, 'Stash-'..id, fromSlot, toSlot, 'ply-'..Player.PlayerData.citizenid, fromAmount)
				end
				other.inventory = ConvertQualityInv(BuildInventory(inv['Stash-'..id]))
				inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
				cb(inventory, other)
			else
				local toItemData = GetItemBySlot("Stash-"..id, toSlot)
				if toItemData ~= nil then
					if toItemData.name ~= fromItemData.name then
						ChangeInv(toItemData.name, "Stash-"..id, toSlot, fromSlot, 'Stash-'..id, toItemData.amount)
						ChangeInv(fromItemData.name, 'Stash-'..id, fromSlot, toSlot, "Stash-"..id, fromAmount)
					else
						local success = compareArrays(toItemData.info, fromItemData.info)
						if success then
							ChangeInv(fromItemData.name, 'Stash-'..id, fromSlot, toSlot, "Stash-"..id, fromAmount)
							if Player.Offline then return true end
							TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
						end
					end
				else
					ChangeInv(fromItemData.name, 'Stash-'..id, fromSlot, toSlot, "Stash-"..id, fromAmount)
				end
				other.inventory = ConvertQualityInv(BuildInventory(inv['Stash-'..id]))
				inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
				cb(inventory, other)
			end
		else
			TriggerClientEvent("QBCore:Notify", src, "You don't have this item!", "error")
		end
	elseif QBCore.Shared.SplitStr(fromInventory, "-")[1] == "itemshop" then
		local shopType = QBCore.Shared.SplitStr(fromInventory, "-")[2]
		local itemData = ShopItems[shopType].items[fromSlot]
		local itemInfo = QBCore.Shared.Items[itemData.name:lower()]
		local bankBalance = Player.PlayerData.money["bank"]
		local price = tonumber((itemData.price * fromAmount))
		local toItemData= GetItemBySlot('ply-'..Player.PlayerData.citizenid, toSlot)
		if toItemData == nil then
			if QBCore.Shared.SplitStr(shopType, "_")[1] == "Dealer" then
				if QBCore.Shared.SplitStr(itemData.name, "_")[1] == "weapon" then
					price = tonumber(itemData.price)
					if Player.Functions.RemoveMoney("cash", price, "dealer-item-bought") then
						itemData.info.serie = tostring(QBCore.Shared.RandomInt(2) .. QBCore.Shared.RandomStr(3) .. QBCore.Shared.RandomInt(1) .. QBCore.Shared.RandomStr(2) .. QBCore.Shared.RandomInt(3) .. QBCore.Shared.RandomStr(4))
						AddItem(src, itemData.name, 1, toSlot, itemData.info)
						TriggerClientEvent('qb-drugs:client:updateDealerItems', src, itemData, 1)
						QBCore.Functions.Notify(src, itemInfo["label"] .. " bought!", "success")
						TriggerEvent("qb-log:server:CreateLog", "dealers", "Dealer item bought", "green", "**"..GetPlayerName(src) .. "** bought a " .. itemInfo["label"] .. " for $"..price)
					else
						QBCore.Functions.Notify(src, "You don\'t have enough cash..", "error")
					end
				else
					if Player.Functions.RemoveMoney("cash", price, "dealer-item-bought") then
						AddItem(src, itemData.name, fromAmount, toSlot, itemData.info)
						TriggerClientEvent('qb-drugs:client:updateDealerItems', src, itemData, fromAmount)
						QBCore.Functions.Notify(src, itemInfo["label"] .. " bought!", "success")
						TriggerEvent("qb-log:server:CreateLog", "dealers", "Dealer item bought", "green", "**"..GetPlayerName(src) .. "** bought a " .. itemInfo["label"] .. "  for $"..price)
					else
						QBCore.Functions.Notify(src, "You don't have enough cash..", "error")
					end
				end
			elseif QBCore.Shared.SplitStr(shopType, "_")[1] == "Itemshop" then
				if Player.Functions.RemoveMoney("cash", price, "itemshop-bought-item") then
					if QBCore.Shared.SplitStr(itemData.name, "_")[1] == "weapon" then
						itemData.info.serie = tostring(QBCore.Shared.RandomInt(2) .. QBCore.Shared.RandomStr(3) .. QBCore.Shared.RandomInt(1) .. QBCore.Shared.RandomStr(2) .. QBCore.Shared.RandomInt(3) .. QBCore.Shared.RandomStr(4))
					end
					local serial = itemData.info.serie
					local imageurl = ("https://cfx-nui-ps-inventory/html/images/%s.png"):format(itemData.name)
					local notes = "Purchased at Ammunation"
					local owner = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
					local weapClass = 1
					local weapModel = QBCore.Shared.Items[itemData.name].label
					AddItem(src, itemData.name, fromAmount, toSlot, itemData.info)
					TriggerClientEvent('qb-shops:client:UpdateShop', src, QBCore.Shared.SplitStr(shopType, "_")[2], itemData, fromAmount)
					QBCore.Functions.Notify(src, itemInfo["label"] .. " bought!", "success")
				--	exports['ps-mdt']:CreateWeaponInfo(serial, imageurl, notes, owner, weapClass, weapModel)
					TriggerEvent("qb-log:server:CreateLog", "shops", "Shop item bought", "green", "**"..GetPlayerName(src) .. "** bought a " .. itemInfo["label"] .. " for $"..price)
				elseif bankBalance >= price then
					Player.Functions.RemoveMoney("bank", price, "itemshop-bought-item")
					if QBCore.Shared.SplitStr(itemData.name, "_")[1] == "weapon" then
						itemData.info.serie = tostring(QBCore.Shared.RandomInt(2) .. QBCore.Shared.RandomStr(3) .. QBCore.Shared.RandomInt(1) .. QBCore.Shared.RandomStr(2) .. QBCore.Shared.RandomInt(3) .. QBCore.Shared.RandomStr(4))
					end
					local serial = itemData.info.serie
					local imageurl = ("https://cfx-nui-ps-inventory/html/images/%s.png"):format(itemData.name)
					local notes = "Purchased at Ammunation"
					local owner = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
					local weapClass = 1
					local weapModel = QBCore.Shared.Items[itemData.name].label
					AddItem(src, itemData.name, fromAmount, toSlot, itemData.info)
					TriggerClientEvent('qb-shops:client:UpdateShop', src, QBCore.Shared.SplitStr(shopType, "_")[2], itemData, fromAmount)
					QBCore.Functions.Notify(src, itemInfo["label"] .. " bought!", "success")
				--	exports['ps-mdt']:CreateWeaponInfo(serial, imageurl, notes, owner, weapClass, weapModel)
					TriggerEvent("qb-log:server:CreateLog", "shops", "Shop item bought", "green", "**"..GetPlayerName(src) .. "** bought a " .. itemInfo["label"] .. " for $"..price)
				else
					QBCore.Functions.Notify(src, "You don't have enough cash..", "error")
				end
			else
				if Player.Functions.RemoveMoney("cash", price, "unkown-itemshop-bought-item") then
					AddItem(src, itemData.name, fromAmount, toSlot, itemData.info)
					QBCore.Functions.Notify(src, itemInfo["label"] .. " bought!", "success")
					TriggerEvent("qb-log:server:CreateLog", "shops", "Shop item bought", "green", "**"..GetPlayerName(src) .. "** bought a " .. itemInfo["label"] .. " for $"..price)
				elseif bankBalance >= price then
					Player.Functions.RemoveMoney("bank", price, "unkown-itemshop-bought-item")
					AddItem(src, itemData.name, fromAmount, toSlot, itemData.info)
					QBCore.Functions.Notify(src, itemInfo["label"] .. " bought!", "success")
					TriggerEvent("qb-log:server:CreateLog", "shops", "Shop item bought", "green", "**"..GetPlayerName(src) .. "** bought a " .. itemInfo["label"] .. " for $"..price)
				else
					TriggerClientEvent('QBCore:Notify', src, "You don\'t have enough cash..", "error")
				end
			end
		end
		inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
		cb(inventory)
	else
		local id = fromInventory
		other.inventory = BuildInventory(inv['Drop-'..id])
		other.name = Drops[id].name
		other.label = Drops[id].label
		other.slots = Drops[id].slots
		other.maxweight = Drops[id].maxweight
		local fromItemData = GetItemBySlot("Drop-"..id, fromSlot)
		if fromItemData and fromItemData.amount >= fromAmount then
			if toInventory == "player" or toInventory == "hotbar" then
				local toItemData = GetItemBySlot('ply-'..Player.PlayerData.citizenid, toSlot)
				if toItemData ~= nil then
					if toItemData.name ~= fromItemData.name then
						ChangeInv(toItemData.name, 'ply-'..Player.PlayerData.citizenid, toSlot, fromSlot, 'Drop-'..id, toItemData.amount)
						ChangeInv(fromItemData.name, 'Drop-'..id, fromSlot, toSlot, 'ply-'..Player.PlayerData.citizenid, fromAmount)
					else
						local success = compareArrays(toItemData.info, fromItemData.info)
						if success then
							ChangeInv(fromItemData.name, 'Drop-'..id, fromSlot, toSlot, 'ply-'..Player.PlayerData.citizenid, fromAmount)
							if Player.Offline then return true end
							TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
						end
					end
				else
					ChangeInv(fromItemData.name, 'Drop-'..id, fromSlot, toSlot, 'ply-'..Player.PlayerData.citizenid, fromAmount)
				end
				other.inventory = ConvertQualityInv(BuildInventory(inv['Drop-'..id]))
				inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
				cb(inventory, other)
			else
				local toItemData = GetItemBySlot("Drop-"..id, toSlot)
				if toItemData ~= nil then
					if toItemData.name ~= fromItemData.name then
						ChangeInv(toItemData.name, 'Drop-'..id, toSlot, fromSlot, 'Drop-'..id, toItemData.amount)
						ChangeInv(fromItemData.name, 'Drop-'..id, fromSlot, toSlot, 'Drop-'..id, fromAmount)
					else
						local success = compareArrays(toItemData.info, fromItemData.info)
						if success then
							ChangeInv(fromItemData.name, 'Drop-'..id, fromSlot, toSlot, 'Drop-'..id, fromAmount)
							if Player.Offline then return true end
							TriggerEvent('qb-log:server:CreateLog', 'playerinventory', 'SwapItem', 'green', '**' .. GetPlayerName(src) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. src .. ')** Swap from: [slot:' .. fromSlot.. " amount"..fromAmount .. '] to [slot:' .. toSlot.. '], itemname: ' .. fromItemData.name)
						end
					end
				else
					ChangeInv(fromItemData.name, 'Drop-'..id, fromSlot, toSlot, 'Drop-'..id, fromAmount)
				end
				other.inventory = ConvertQualityInv(BuildInventory(inv['Drop-'..id]))
				inventory = ConvertQualityInv(BuildInventory(inv['ply-'..Player.PlayerData.citizenid]))
				cb(inventory, other)
			end
		else
			TriggerClientEvent("QBCore:Notify", src, "You don't have this item!", "error")
		end
	end
end)

RegisterServerEvent("inventory:server:GiveItem", function(target, name, amount, slot)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
	target = tonumber(target)
    local OtherPlayer = QBCore.Functions.GetPlayer(target)
    local dist = #(GetEntityCoords(GetPlayerPed(src))-GetEntityCoords(GetPlayerPed(target)))
	if Player == OtherPlayer then return QBCore.Functions.Notify(src, "You can\'t give yourself an item?") end
	if dist > 2 then return QBCore.Functions.Notify(src, "You are too far away to give items!") end
	local item = GetItemBySlot(src, slot)
	if not item then QBCore.Functions.Notify(src, "Item you tried giving not found!"); return end
	if item.name ~= name then QBCore.Functions.Notify(src, "Incorrect item found try again!"); return end
	if amount <= item.amount then
		if amount == 0 then
			amount = item.amount
		end
		if RemoveItem(src, item.name, amount, item.slot) then
			if AddItem(target, item.name, amount, false, item.info, item.created) then
				TriggerClientEvent('inventory:client:ItemBox',target, QBCore.Shared.Items[item.name], "add")
				QBCore.Functions.Notify(target, "You Received "..amount..' '..item.label.." From "..Player.PlayerData.charinfo.firstname.." "..Player.PlayerData.charinfo.lastname)
				TriggerClientEvent("inventory:client:UpdatePlayerInventory", target, true)
				TriggerClientEvent('inventory:client:ItemBox',src, QBCore.Shared.Items[item.name], "remove")
				QBCore.Functions.Notify(src, "You gave " .. OtherPlayer.PlayerData.charinfo.firstname.." "..OtherPlayer.PlayerData.charinfo.lastname.. " " .. amount .. " " .. item.label .."!")
				TriggerClientEvent("inventory:client:UpdatePlayerInventory", src, true)
				TriggerClientEvent('qb-inventory:client:giveAnim', src)
				TriggerClientEvent('qb-inventory:client:giveAnim', target)
			else
				AddItem(src, item.name, amount, item.slot, item.info, item.created)
				QBCore.Functions.Notify(src, "The other players inventory is full!", "error")
				QBCore.Functions.Notify(target, "The other players inventory is full!", "error")
				TriggerClientEvent("inventory:client:UpdatePlayerInventory", src, false)
				TriggerClientEvent("inventory:client:UpdatePlayerInventory", target, false)
			end
		else
			TriggerClientEvent('QBCore:Notify', src,  "You do not have enough of the item", "error")
		end
	else
		TriggerClientEvent('QBCore:Notify', src, "You do not have enough items to transfer")
	end
end)

RegisterNetEvent('inventory:server:snowball', function(action)
	if action == "add" then
		AddItem(source, "weapon_snowball")
	elseif action == "remove" then
		RemoveItem(source, "weapon_snowball")
	end
end)

-- callback

QBCore.Functions.CreateCallback('qb-inventory:server:GetStashItems', function(source, cb, stashId)
	cb(GetStashItems(stashId))
end)

QBCore.Functions.CreateCallback('inventory:server:GetCurrentDrops', function(_, cb)
	cb(Drops)
end)

QBCore.Functions.CreateCallback('QBCore:HasItem', function(source, cb, items, amount)
	cb(HasItem(source, items, amount))
end)

-- command

QBCore.Commands.Add("resetinv", "Reset Inventory (Admin Only)", {{name="type", help="stash/trunk/glovebox"},{name="id/plate", help="ID of stash or license plate"}}, true, function(source, args)
	local invType = args[1]:lower()
	table.remove(args, 1)
	local invId = table.concat(args, " ")
	if invType and invId then
		if invType == "trunk" then
			if Trunks[invId] then
				Trunks[invId].isOpen = false
			end
		elseif invType == "glovebox" then
			if Gloveboxes[invId] then
				Gloveboxes[invId].isOpen = false
			end
		elseif invType == "stash" then
			if Stashes[invId] then
				Stashes[invId].isOpen = false
			end
		else
			TriggerClientEvent('QBCore:Notify', source,  "Not a valid type..", "error")
		end
	else
		TriggerClientEvent('QBCore:Notify', source,  "Arguments not filled out correctly..", "error")
	end
end, "admin")

QBCore.Commands.Add("rob", "Rob Player", {}, false, function(source, args)
	TriggerClientEvent("police:client:RobPlayer", source)
end)

QBCore.Commands.Add("giveitem", "Give An Item (Admin Only)", {{name="id", help="Player ID"},{name="item", help="Name of the item (not a label)"}, {name="amount", help="Amount of items"}}, false, function(source, args)
	local id = tonumber(args[1])
	local Player = QBCore.Functions.GetPlayer(id)
	local amount = tonumber(args[3]) or 1
	local itemData = QBCore.Shared.Items[tostring(args[2]):lower()]
	if Player then
			if itemData then
				-- check iteminfo
				local info = {}
				if itemData["name"] == "id_card" then
					info.citizenid = Player.PlayerData.citizenid
					info.firstname = Player.PlayerData.charinfo.firstname
					info.lastname = Player.PlayerData.charinfo.lastname
					info.birthdate = Player.PlayerData.charinfo.birthdate
					info.gender = Player.PlayerData.charinfo.gender
					info.nationality = Player.PlayerData.charinfo.nationality
				elseif itemData["name"] == "driver_license" then
					info.firstname = Player.PlayerData.charinfo.firstname
					info.lastname = Player.PlayerData.charinfo.lastname
					info.birthdate = Player.PlayerData.charinfo.birthdate
					info.type = "Class C Driver License"
				elseif itemData["type"] == "weapon" then
					amount = 1
					info.serie = tostring(QBCore.Shared.RandomInt(2) .. QBCore.Shared.RandomStr(3) .. QBCore.Shared.RandomInt(1) .. QBCore.Shared.RandomStr(2) .. QBCore.Shared.RandomInt(3) .. QBCore.Shared.RandomStr(4))
					info.quality = 100
				elseif itemData["name"] == "harness" then
					info.uses = 20
				elseif itemData["name"] == "markedbills" then
					info.worth = math.random(5000, 10000)
				elseif itemData["name"] == "labkey" then
					info.lab = exports["qb-methlab"]:GenerateRandomLab()
				elseif itemData["name"] == "printerdocument" then
					info.url = "https://cdn.discordapp.com/attachments/870094209783308299/870104331142189126/Logo_-_Display_Picture_-_Stylized_-_Red.png"
				elseif QBCore.Shared.Items[itemData["name"]]["decay"] and QBCore.Shared.Items[itemData["name"]]["decay"] > 0 then
					info.quality = 100
				end

				if AddItem(id, itemData["name"], amount, false, info) then
					QBCore.Functions.Notify(source, "You Have Given " ..GetPlayerName(id).." "..amount.." "..itemData["name"].. "", "success")
				else
					QBCore.Functions.Notify(source, "Can\'t give item!", "error")
				end
			else
				QBCore.Functions.Notify(source, "Item Does Not Exist", "error")
			end
	else
		QBCore.Functions.Notify(source,  "Player Is Not Online", "error")
	end
end, "admin")

QBCore.Commands.Add("randomitems", "Give Random Items (God Only)", {}, false, function(source, _)
	local filteredItems = {}
	for k, v in pairs(QBCore.Shared.Items) do
		if QBCore.Shared.Items[k]["type"] ~= "weapon" then
			filteredItems[#filteredItems+1] = v
		end
	end
	for _ = 1, 10, 1 do
		local randitem = filteredItems[math.random(1, #filteredItems)]
		local amount = math.random(1, 10)
		if randitem["unique"] then
			amount = 1
		end
		if AddItem(source, randitem["name"], amount) then
			TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[randitem["name"]], 'add')
            Wait(500)
		end
	end
end, "god")

QBCore.Commands.Add('clearinv', 'Clear Players Inventory (Admin Only)', { { name = 'id', help = 'Player ID' } }, false, function(source, args)
    local playerId = args[1] ~= '' and tonumber(args[1]) or source
    local Player = QBCore.Functions.GetPlayer(playerId)
    if Player then
        ClearInventory(playerId)
    else
        QBCore.Functions.Notify(source, "Player not online", 'error')
    end
end, 'admin')

-- item

-- QBCore.Functions.CreateUseableItem("snowball", function(source, item)
-- 	local Player = QBCore.Functions.GetPlayer(source)
-- 	local itemData = Player.Functions.GetItemBySlot(item.slot)       -- --- DID THIS GET PUT ELSEWHERE?? IDK
-- 	if Player.Functions.GetItemBySlot(item.slot) then
--         TriggerClientEvent("inventory:client:UseSnowball", source, itemData.amount)
--     end
-- end)

CreateUsableItem("driver_license", function(source, item)
	local playerPed = GetPlayerPed(source)
	local playerCoords = GetEntityCoords(playerPed)
	local players = QBCore.Functions.GetPlayers()
	for _, v in pairs(players) do
		local targetPed = GetPlayerPed(v)
		local dist = #(playerCoords - GetEntityCoords(targetPed))
		if dist < 3.0 then
			TriggerClientEvent('chat:addMessage', v,  {
					template = '<div class="chat-message advert"><div class="chat-message-body"><strong>{0}:</strong><br><br> <strong>First Name:</strong> {1} <br><strong>Last Name:</strong> {2} <br><strong>Birth Date:</strong> {3} <br><strong>Licenses:</strong> {4}</div></div>',
					args = {
						"Drivers License",
						item.info.firstname,
						item.info.lastname,
						item.info.birthdate,
						item.info.type
					}
				}
			)
		end
	end
end)

CreateUsableItem("id_card", function(source, item)
	local playerPed = GetPlayerPed(source)
	local playerCoords = GetEntityCoords(playerPed)
	local players = QBCore.Functions.GetPlayers()
	for _, v in pairs(players) do
		local targetPed = GetPlayerPed(v)
		local dist = #(playerCoords - GetEntityCoords(targetPed))
		if dist < 3.0 then
			local gender = "Man"
			if item.info.gender == 1 then
				gender = "Woman"
			end
			TriggerClientEvent('chat:addMessage', v,  {
					template = '<div class="chat-message advert"><div class="chat-message-body"><strong>{0}:</strong><br><br> <strong>Civ ID:</strong> {1} <br><strong>First Name:</strong> {2} <br><strong>Last Name:</strong> {3} <br><strong>Birthdate:</strong> {4} <br><strong>Gender:</strong> {5} <br><strong>Nationality:</strong> {6}</div></div>',
					args = {
						"ID Card",
						item.info.citizenid,
						item.info.firstname,
						item.info.lastname,
						item.info.birthdate,
						gender,
						item.info.nationality
					}
				}
			)
		end
	end
end)


CreateThread(function()
	while true do
		for k, v in pairs(Drops) do
			if v and (v.createdTime + Config.CleanupDropTime < os.time()) and not Drops[k].isOpen then
				Drops[k] = nil
				TriggerClientEvent("inventory:client:RemoveDropItem", -1, k)
			end
		end
		Wait(60 * 1000)
	end
end)

QBCore.Functions.CreateCallback('inventory:server:ConvertQuality', function(source, cb, inventory, other)
    local src = source
    local data = {}
    for _, item in pairs(inventory) do
        if item.created then
            if QBCore.Shared.Items[item.name:lower()]["decay"] ~= nil or QBCore.Shared.Items[item.name:lower()]["decay"] ~= 0 then
                local quality = ConvertQuality(item)
                inventory[_].quality = quality
            end
        end
    end
    if other then
		for _, item in pairs(other.inventory) do
			if item.created then
				if QBCore.Shared.Items[item.name:lower()]["decay"] ~= nil or QBCore.Shared.Items[item.name:lower()]["decay"] ~= 0 then
					local quality = ConvertQuality(item)
					other.inventory[_].quality = quality
				end
			end
		end
    end
    data.inventory = inventory
    data.other = other
    cb(data)
end)
