NexusCraftingUtils = {}

function NexusCraftingUtils.getStation(stationId)
    if type(stationId) ~= 'string' then return nil end
    return NexusCraftingConfig.stations[stationId]
end

function NexusCraftingUtils.getRecipe(recipeId)
    if type(recipeId) ~= 'string' then return nil end
    return NexusCraftingConfig.recipes[recipeId]
end

function NexusCraftingUtils.recipeAllowedAtStation(station, recipeId)
    if type(station) ~= 'table' or type(station.recipes) ~= 'table' then return false end

    for i = 1, #station.recipes do
        if station.recipes[i] == recipeId then return true end
    end

    return false
end

function NexusCraftingUtils.copyRecipe(recipe)
    if type(recipe) ~= 'table' then return nil end

    local result = {
        label = recipe.label,
        category = recipe.category,
        output = {
            item = recipe.output.item,
            count = recipe.output.count,
        },
        ingredients = {},
        duration = recipe.duration,
        requiredLevel = recipe.requiredLevel or 1,
        xp = recipe.xp,
        reputation = recipe.reputation,
        blueprint = recipe.blueprint,
        hiddenUntilLevel = recipe.hiddenUntilLevel,
        hiddenUntilReputation = recipe.hiddenUntilReputation,
        risk = recipe.risk,
        sensitive = recipe.sensitive == true,
    }

    for i = 1, #(recipe.ingredients or {}) do
        result.ingredients[i] = {
            item = recipe.ingredients[i].item,
            count = recipe.ingredients[i].count,
        }
    end

    return result
end

function NexusCraftingUtils.getCategory(category)
    return NexusCraftingConfig.categories[category or 'civil'] or NexusCraftingConfig.categories.civil
end
