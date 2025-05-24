local SpamDetector = {}
SpamDetector.__index = SpamDetector

local DEFAULT_CONFIG = {
    spam_threshold = 55,
    ml_model_path = "../addons/shhml/spam_model.lua",
    ml_positive_score_on_spam = 100,
    ml_negative_score_on_ham = -50,
    message_history_length = 10,
    repeat_message_threshold = 5,
    repeat_message_score = 35,
}


local ml_model_data = nil
local log_prob_unknown_spam = nil
local log_prob_unknown_ham = nil

local function extractActualMessageLua(fullMessage)
    local actualMsg = string.match(fullMessage, "^%s*%[..:..:..%]%s+[^%[%]]+%[[^%]]+%]:%s*(.*)$")
    if not actualMsg then
        actualMsg = string.match(fullMessage, "^%s*%[..:..:..%]%s+[^:]+:%s*(.*)$")
    end
    if not actualMsg then
        actualMsg = string.match(fullMessage, "^.-%s*:%s*(.*)$")
    end
    return (actualMsg or fullMessage):match("^%s*(.-)%s*$")
end


local function preprocessTextLua(text)
    if not text or text == "" then return {} end
    local extractedMessage = extractActualMessageLua(text)
    local lowerCaseMessage = string.lower(extractedMessage)

    local cleanedMessage = string.gsub(lowerCaseMessage, "[^a-z0-9%s]", " ")
    cleanedMessage = string.gsub(cleanedMessage, "%s+", " ")
    cleanedMessage = string.gsub(cleanedMessage, "^%s*(.-)%s*$", "%1")

    local words = {}
    if cleanedMessage ~= "" then
        for word in string.gmatch(cleanedMessage, "[a-z0-9]+") do
            if string.len(word) > 1 then
                table.insert(words, word)
            end
        end
    end
    return words
end

local function predictSpamFromModel(messageText)
    if not ml_model_data then
        print("ERROR: ML Model not loaded. Cannot predict.")
        return "ham", 0, -100
    end

    local words = preprocessTextLua(messageText)

    local logProbMessageIsSpam = math.log(ml_model_data.prob_spam)
    local logProbMessageIsHam = math.log(ml_model_data.prob_ham)

    for _, word in ipairs(words) do
        if ml_model_data.word_probs_spam[word] then
            logProbMessageIsSpam = logProbMessageIsSpam + math.log(ml_model_data.word_probs_spam[word])
        else
            logProbMessageIsSpam = logProbMessageIsSpam + log_prob_unknown_spam
        end

        if ml_model_data.word_probs_ham[word] then
            logProbMessageIsHam = logProbMessageIsHam + math.log(ml_model_data.word_probs_ham[word])
        else
            logProbMessageIsHam = logProbMessageIsHam + log_prob_unknown_ham
        end
    end

    local result = "ham"
    if logProbMessageIsSpam > logProbMessageIsHam then
        result = "spam"
    end
    
    return result, logProbMessageIsSpam, logProbMessageIsHam
end


function SpamDetector:new(config)
    local instance = setmetatable({}, SpamDetector)
    instance.config = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        instance.config[k] = config and config[k] or v
    end

    instance.player_message_history = {}
    instance.whitelisted_players = {}
    instance.blacklisted_players = {}

    if not instance:_load_model(instance.config.ml_model_path) then
        print("WARNING: Failed to load ML model. Spam detection will be impaired.")
    end
    return instance
end

function SpamDetector:_load_model(filepath)
    local success, model_or_error = pcall(dofile, filepath)
    if success and type(model_or_error) == "table" then
        ml_model_data = model_or_error
        if not ml_model_data.alpha or not ml_model_data.total_words_in_spam_docs or
           not ml_model_data.vocabulary_size or not ml_model_data.total_words_in_ham_docs then
            print("ERROR: Loaded ML model is missing essential fields (alpha, total_words_*, vocabulary_size).")
            ml_model_data = nil
            return false
        end

        
        local denominator_spam = ml_model_data.total_words_in_spam_docs + ml_model_data.alpha * ml_model_data.vocabulary_size
        local denominator_ham = ml_model_data.total_words_in_ham_docs + ml_model_data.alpha * ml_model_data.vocabulary_size

        if denominator_spam == 0 then denominator_spam = 1 end
        if denominator_ham == 0 then denominator_ham = 1 end

        log_prob_unknown_spam = math.log( ml_model_data.alpha / denominator_spam )
        log_prob_unknown_ham  = math.log( ml_model_data.alpha / denominator_ham )
        
        print("ML Model loaded successfully from: " .. filepath)
        return true
    else
        print("ERROR loading ML model from '" .. filepath .. "': " .. tostring(model_or_error))
        ml_model_data = nil
        return false
    end
end

function SpamDetector:add_whitelisted_player(player)
    self.whitelisted_players[string.lower(player)] = true
    print("Player whitelisted: " .. player)
end

function SpamDetector:remove_whitelisted_player(player)
    self.whitelisted_players[string.lower(player)] = nil
    print("Player removed from whitelist: " .. player)
end

function SpamDetector:add_blacklisted_player(player)
    self.blacklisted_players[string.lower(player)] = true
    print("Player blacklisted: " .. player)
end

function SpamDetector:remove_blacklisted_player(player)
    self.blacklisted_players[string.lower(player)] = nil
    print("Player removed from blacklist: " .. player)
end

function SpamDetector:_update_message_history(player, message_content)
    if not self.player_message_history[player] then
        self.player_message_history[player] = {}
    end
    local history = self.player_message_history[player]
    table.insert(history, 1, message_content)
    
    while #history > self.config.message_history_length do
        table.remove(history)
    end
end

function SpamDetector:_check_repeat_messages(player, message_content)
    local history = self.player_message_history[player]
    if not history then return 0 end

    local repeat_count = 0
    for _, old_message in ipairs(history) do
        if old_message == message_content then
            repeat_count = repeat_count + 1
        end
    end
    return repeat_count
end

function SpamDetector:check_message(message_details)
    local player_lower = string.lower(message_details.player) 
    local original_message = message_details.full_message_string
    local extracted_message_content = extractActualMessageLua(original_message)

    local current_score = 0
    local reasons = {}
    local is_spam_final = false

    
    if self.whitelisted_players[player_lower] then
        return false, 0, {"Player is whitelisted"}
    end
    if self.blacklisted_players[player_lower] then
        return true, 1000, {"Player is blacklisted"}
    end

    
    if not ml_model_data then
        table.insert(reasons, "ML Model Not Loaded")
    else
        local ml_result, log_spam, log_ham = predictSpamFromModel(original_message)

        if ml_result == "spam" then
            current_score = current_score + self.config.ml_positive_score_on_spam
            table.insert(reasons, string.format("ML: Classified as Spam (S:%.2f, H:%.2f)", log_spam, log_ham))
        else
            current_score = current_score + self.config.ml_negative_score_on_ham
            table.insert(reasons, string.format("ML: Classified as Ham (S:%.2f, H:%.2f)", log_spam, log_ham))
        end
    end

    
    local repeat_count = self:_check_repeat_messages(player_lower, extracted_message_content)
    if repeat_count >= self.config.repeat_message_threshold then
        current_score = current_score + self.config.repeat_message_score
        table.insert(reasons, string.format("Rapid Repeat: Message seen %d times in recent history.", repeat_count))
    end
    self:_update_message_history(player_lower, extracted_message_content)

    is_spam_final = current_score >= self.config.spam_threshold
    
    
    if is_spam_final then
        if self.config and self.config.log_level and self.config.log_level >= 1 then 
            print(string.format("SPAM: Player %s, Score: %d, Reasons: [%s], Msg: %s",
                message_details.player, current_score, table.concat(reasons, "; "), extracted_message_content)) 
        end
    else
        if self.config and self.config.log_level and self.config.log_level >= 2 then 
            print(string.format("HAM: Player %s, Score: %d, Reasons: [%s], Msg: %s",
                message_details.player, current_score, table.concat(reasons, "; "), extracted_message_content)) 
        end
    end

    return is_spam_final, current_score, reasons
end

return SpamDetector