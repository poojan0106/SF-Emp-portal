/*
----------------------------------------------------------------------------
ClaudeAIService.cls - FIXED WITH PREFILL
Forces Claude to ask ONLY questions from the predefined list
Uses prefill technique to guarantee correct questions
----------------------------------------------------------------------------
*/
public with sharing class ClaudeAIService {
    
    private static final String API_ENDPOINT = 'https://api.anthropic.com/v1/messages';
    private static final String MODEL = 'claude-opus-4-6';
    private static final Integer MAX_TOKENS = 4096;
    
    public static final String INPUT_TEXT = 'text';
    public static final String INPUT_NUMBER = 'number';
    public static final String INPUT_DATE = 'date';
    public static final String INPUT_NONE = 'none';
    
    // Main method - questionCount is now String
    public static AIResponse generateResponse(String userMessage, BlakeneyChatService.ChatContext ctx, 
                                              String contextType, String questionCount) {
        System.debug('═══════════════════════════════════════════════════════');
        System.debug('🎯 ClaudeAIService.generateResponse CALLED');
        System.debug('   User Message: ' + userMessage);
        System.debug('   Question Count (RECEIVED): ' + questionCount);
        System.debug('   Context Type: ' + contextType);
        
        // Convert to integer
        Integer qNum = 0;
        try {
            qNum = Integer.valueOf(questionCount);
        } catch (Exception e) {
            qNum = 0;
        }
        
        // SAFETY CHECK: If we've completed all 12 questions (0-11), return completion message
        if (qNum >= 12) {
            System.debug('✅ ALL QUESTIONS COMPLETED - Returning completion message');
            return generateCompletionResponse();
        }
        
        List<String> questionList = new List<String>{
            'Q0: Greeting',
            'Q1: Short-term (6 months)',
            'Q2: Medium-term (2-5 years)',
            'Q3: Long-term (10+ years)',
            'Q4: Dream job',
            'Q5: Work location/relocating',
            'Q6: Remote preference',
            'Q7: Minimum salary',
            'Q8: Maximum salary',
            'Q9: Company size',
            'Q10: Industries',
            'Q11: Current role'
        };
        
        String expectedQuestion = qNum < questionList.size() ? questionList[qNum] : 'COMPLETE';
        System.debug('   📋 Should ask: ' + expectedQuestion);
        System.debug('═══════════════════════════════════════════════════════');
        
        // Get the exact question text for prefill
        String exactQuestion = getExpectedQuestion(questionCount);
        System.debug('   📝 Exact question for prefill: ' + exactQuestion);
        
        List<Map<String, String>> messages = buildMessageHistory(ctx, userMessage);
        String systemPrompt = buildSystemPrompt(ctx, contextType, questionCount);
        HttpResponse response = callClaudeAPI(systemPrompt, messages, exactQuestion);
        System.debug('Claude API Response: ' + response.getBody());
        AIResponse aiResp = parseResponse(response, questionCount);
        
        // If Claude went off-script, use fallback scripted response
        if (aiResp.error == 'OFF_SCRIPT_RESPONSE_DETECTED') {
            System.debug('⚠️ OFF-SCRIPT DETECTED - Using Fallback for question #' + questionCount);
            aiResp = generateFallbackResponse(questionCount);
        }
        
        System.debug('✅ Final Response Generated');
        System.debug('   Content: ' + aiResp.content);
        System.debug('   Question count remains: ' + questionCount + ' (increment happens in calling code)');
        System.debug('═══════════════════════════════════════════════════════');
        
        return aiResp;
    }

    private static String buildSystemPrompt(BlakeneyChatService.ChatContext ctx, String contextType, String questionCount) {
        String basePrompt = getBaseSystemPrompt();
        String contextPrompt = getContextSpecificPrompt(contextType);
        String candidateContext = buildCandidateContext(ctx, questionCount);
        return basePrompt + '\n\n' + contextPrompt + '\n\n' + candidateContext;
    }
    
    private static String getBaseSystemPrompt() {
        return 'You are Blakeney, a friendly career assistant collecting candidate information.\n\n' +
               'RULES:\n' +
               '1. Ask the EXACT question provided in "NEXT QUESTION TO ASK" below\n' +
               '2. Keep your response to 2 sentences maximum\n' +
               '3. Format: Brief acknowledgment + the exact question\n' +
               '4. Do not create your own questions\n' +
               '5. Do not substitute different questions\n\n' +
               'Example response: "Got it! [EXACT QUESTION FROM BELOW]"\n';
    }
    
    private static String getContextSpecificPrompt(String contextType) {
        return 'CONTEXT: ' + contextType + '\n' +
               'You must ask the exact question specified below.\n';
    }
    
    private static String buildCandidateContext(BlakeneyChatService.ChatContext ctx, String questionCount) {
        // Convert String to Integer
        Integer questionsAsked = 0;
        if (String.isNotBlank(questionCount)) {
            try {
                questionsAsked = Integer.valueOf(questionCount);
            } catch (Exception e) {
                questionsAsked = 0;
            }
        }
        
        // Define the exact sequence of questions
        List<String> questionSequence = new List<String>{
            'FIELD_0: Greetings - Ask: "Hi! I\'m Blakeney, your personal career agent. I\'m here to help you discover opportunities. Ready to get started?"',
            'FIELD_1: Short-term career goal (next 6 months) - Ask: "What are you hoping to achieve in your career over the next 6 months?"',
            'FIELD_2: Medium-term career goal (2-5 years) - Ask: "Where do you see yourself in 2-5 years?"',
            'FIELD_3: Long-term career goal (10+ years) - Ask: "What\'s your long-term career aspiration? Where do you see yourself in 10+ years?"',
            'FIELD_4: Dream job (aspirational) - Ask: "If you could have any job in the world, what would your absolute dream role be?"',
            'FIELD_5: Preferred work location(s) - Ask: "Where would you like to work? Are you open to relocating?"',
            'FIELD_6: Remote work preference - Ask: "What\'s your preference for remote work?"',
            'FIELD_7: Minimum acceptable salary - Ask: "What\'s the minimum salary you\'d consider for your next role?"',
            'FIELD_8: Maximum salary expectation - Ask: "What\'s your maximum salary expectation?"',
            'FIELD_9: Preferred company size - Ask: "What size company do you prefer working for?"',
            'FIELD_10: Industry preferences - Ask: "What industries are you most interested in?"',
            'FIELD_11: Current Role - Ask: "What is your current role in your company?"',
            'FIELD_12: Skills - Ask: "What tools, technologies, or software have you worked with? Add your technical and professional skills."'
        };
        
        // Determine NEXT question to ask
        String nextQuestion = '';
        String completionStatus = '';
        String exactQuestionText = '';
        
        if (questionsAsked >= questionSequence.size()) {
            nextQuestion = 'ALL FIELDS COLLECTED - Thank the candidate warmly and let them know their profile is complete.';
            completionStatus = 'COMPLETE - All 13 fields collected';
            exactQuestionText = 'Congratulations! Your profile is complete.';
        } else {
            nextQuestion = questionSequence[questionsAsked];
            completionStatus = 'IN_PROGRESS - Collecting field ' + (questionsAsked + 1) + ' of ' + questionSequence.size();
            
            // Extract the exact question text
            Integer askIndex = nextQuestion.indexOf('Ask: "');
            if (askIndex != -1) {
                exactQuestionText = nextQuestion.substring(askIndex + 6);
                exactQuestionText = exactQuestionText.substring(0, exactQuestionText.length() - 1); // Remove trailing "
            }
        }
        
        // Build simplified context
        String context = '═══════════════════════════════════════════════════════════════\n';
        context += 'CONVERSATION STATE\n';
        context += '═══════════════════════════════════════════════════════════════\n';
        context += 'Questions asked so far: ' + questionsAsked + '\n';
        context += 'Current status: ' + completionStatus + '\n';
        context += 'Total questions in script: ' + questionSequence.size() + '\n\n';
        
        // Show already collected fields
        context += '═══════════════════════════════════════════════════════════════\n';
        context += 'ALREADY COLLECTED (DO NOT ASK AGAIN)\n';
        context += '═══════════════════════════════════════════════════════════════\n';
        if (questionsAsked == 0) {
            context += '(None yet - this is the first question)\n\n';
        } else {
            for (Integer i = 0; i < questionsAsked && i < questionSequence.size(); i++) {
                String fieldInfo = questionSequence[i];
                String fieldName = fieldInfo.substringBefore(':').trim();
                context += '✓ ' + fieldName + ' - ALREADY ANSWERED\n';
            }
            context += '\n';
        }
        
        // THE NEXT QUESTION
        context += '═══════════════════════════════════════════════════════════════\n';
        context += 'NEXT QUESTION TO ASK (USE EXACT WORDING)\n';
        context += '═══════════════════════════════════════════════════════════════\n';
        context += 'FIELD: ' + nextQuestion.substringBefore(':') + '\n';
        context += 'EXACT QUESTION: "' + exactQuestionText + '"\n\n';
        context += 'Your response should be:\n';
        context += '[Brief acknowledgment]! ' + exactQuestionText + '\n';
        context += '═══════════════════════════════════════════════════════════════\n\n';
        
        // List all questions for reference
        context += 'COMPLETE QUESTION SEQUENCE:\n';
        for (Integer i = 0; i < questionSequence.size(); i++) {
            String status = (i < questionsAsked) ? '✅ DONE' : (i == questionsAsked) ? '👉 NEXT' : '⏳ PENDING';
            context += status + ' - ' + questionSequence[i].substringBefore(':') + '\n';
        }
        context += '═══════════════════════════════════════════════════════════════\n';
        
        return context;
    }
    
    private static List<Map<String, String>> buildMessageHistory(BlakeneyChatService.ChatContext ctx, String currentMessage) {
        List<Map<String, String>> messages = new List<Map<String, String>>();
        
        // Add recent conversation history (last 10 messages)
        if (ctx.recentMessages != null && !ctx.recentMessages.isEmpty()) {
            List<Chat_Interaction__c> chronological = new List<Chat_Interaction__c>();
            for (Integer i = ctx.recentMessages.size() - 1; i >= 0; i--) {
                chronological.add(ctx.recentMessages[i]);
            }
            
            for (Chat_Interaction__c msg : chronological) {
                String role = msg.Message_Type__c == 'User' ? 'user' : 'assistant';
                messages.add(new Map<String, String>{ 
                    'role' => role, 
                    'content' => msg.Message_Content__c 
                });
            }
        }
        
        // Add current user message
        if (String.isNotBlank(currentMessage)) {
            messages.add(new Map<String, String>{ 
                'role' => 'user', 
                'content' => currentMessage 
            });
        }
        
        return messages;
    }
    
    private static HttpResponse callClaudeAPI(String systemPrompt, List<Map<String, String>> messages, String expectedQuestion) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(API_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-api-key', getAPIKey());
        req.setHeader('anthropic-version', '2023-06-01');
        req.setTimeout(60000);
        
        // ADD PREFILL - Force Claude to start with acknowledgment and begin the question
        // This technique makes Claude complete the sentence we start
        String prefillText = 'Got it!';
        
        messages.add(new Map<String, String>{
            'role' => 'assistant',
            'content' => prefillText
        });
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'model' => MODEL,
            'max_tokens' => MAX_TOKENS,
            'temperature' => 0.1,  // Low temperature for deterministic behavior
            'system' => systemPrompt,
            'messages' => messages
        };
        
        req.setBody(JSON.serialize(requestBody));
        
        System.debug('Claude API Request: ' + JSON.serializePretty(requestBody));
        
        return new Http().send(req);
    }
    
    private static AIResponse parseResponse(HttpResponse response, String questionCount) {
        AIResponse aiResp = new AIResponse();
        aiResp.model = MODEL;
        
        if (response.getStatusCode() == 200) {
            Map<String, Object> respBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            
            // Extract content
            List<Object> content = (List<Object>) respBody.get('content');
            if (content != null && !content.isEmpty()) {
                Map<String, Object> textBlock = (Map<String, Object>) content[0];
                String claudeResponse = (String) textBlock.get('text');
                
                // Prepend the prefill text since Claude only returns the completion
                aiResp.content = 'Got it!' + claudeResponse;
                
                System.debug('Claude raw response: ' + claudeResponse);
                System.debug('Full response with prefill: ' + aiResp.content);
            }
            
            // Extract token usage
            Map<String, Object> usage = (Map<String, Object>) respBody.get('usage');
            if (usage != null) {
                aiResp.inputTokens = (Integer) usage.get('input_tokens');
                aiResp.outputTokens = (Integer) usage.get('output_tokens');
                aiResp.totalTokens = aiResp.inputTokens + aiResp.outputTokens;
            }
            
            // Validation - check for forbidden keywords
            if (containsForbiddenKeywords(aiResp.content)) {
                System.debug(LoggingLevel.WARN, '⚠️ REJECTED - Contains forbidden keywords');
                aiResp.error = 'OFF_SCRIPT_RESPONSE_DETECTED';
            } else {
                System.debug('✅ ACCEPTING RESPONSE');
                detectInputSettings(aiResp);
            }
            
        } else {
            aiResp.content = 'I apologize, but I\'m having trouble connecting. Please try again.';
            aiResp.error = 'API Error: ' + response.getStatusCode() + ' - ' + response.getStatus();
            setDefaultInputSettings(aiResp);
        }
        
        return aiResp;
    }
    
    // Check only for forbidden keywords
    private static Boolean containsForbiddenKeywords(String response) {
        if (String.isBlank(response)) return false;
        
        String lowerResponse = response.toLowerCase();
        
        List<String> forbiddenKeywords = new List<String>{
            'benefits',
            'feedback',
            'work style',
            'motivates you',
            'handle conflict',
            'team player',
            'strengths',
            'weaknesses',
            'past experience',
            'work environment',
            'company culture'
        };
        
        for (String forbidden : forbiddenKeywords) {
            if (lowerResponse.contains(forbidden)) {
                System.debug(LoggingLevel.ERROR, '🚫 FORBIDDEN KEYWORD: "' + forbidden + '"');
                return true;
            }
        }
        
        return false;
    }
    
    private static String getExpectedQuestion(String questionCount) {
        Integer qNum = 0;
        try {
            qNum = Integer.valueOf(questionCount);
        } catch (Exception e) {
            qNum = 0;
        }
        
        List<String> questions = new List<String>{
            'Hi! I\'m Blakeney, your personal career agent. I\'m here to help you discover opportunities. Ready to get started?',  // 0
            'What are you hoping to achieve in your career over the next 6 months?',  // 1
            'Where do you see yourself in 2-5 years?',  // 2
            'What\'s your long-term career aspiration? Where do you see yourself in 10+ years?',  // 3
            'If you could have any job in the world, what would your absolute dream role be?',  // 4
            'Where would you like to work? Are you open to relocating?',  // 5
            'What\'s your preference for remote work?',  // 6
            'What\'s the minimum salary you\'d consider for your next role?',  // 7
            'What\'s your maximum salary expectation?',  // 8
            'What size company do you prefer working for?',  // 9
            'What industries are you most interested in?',  // 10
            'What is your current role in your company?'  // 11
        };
        
        // Questions 0-11 are valid questions
        if (qNum >= 0 && qNum < questions.size()) {
            return questions[qNum];
        } else {
            // Question 12+ means we're done
            return 'Your profile is complete!';
        }
    }
    // Generate completion message when all questions are answered
    private static AIResponse generateCompletionResponse() {
        AIResponse aiResp = new AIResponse();
        aiResp.model = MODEL;
        aiResp.content = 'Congratulations! 🎉 Your profile is complete. You can now explore opportunities or update your preferences anytime.';
        
        // Disable input for completion message
        aiResp.inputActive = false;
        aiResp.inputType = INPUT_NONE;
        aiResp.inputPlaceholder = '';
        aiResp.quickReplies = new List<BlakeneyChatService.QuickReply>();
        
        System.debug('📋 COMPLETION MESSAGE GENERATED');
        
        return aiResp;
    }
    // Generate fallback scripted response when Claude goes off-script
    private static AIResponse generateFallbackResponse(String questionCount) {
        AIResponse aiResp = new AIResponse();
        aiResp.model = MODEL;
        
        Integer questionsAsked = 0;
        if (String.isNotBlank(questionCount)) {
            try {
                questionsAsked = Integer.valueOf(questionCount);
            } catch (Exception e) {
                questionsAsked = 0;
            }
        }
        
        System.debug('📋 GENERATING FALLBACK for question index: ' + questionsAsked);
        
        // If we've completed all questions, return completion message
        if (questionsAsked >= 13) {
            return generateCompletionResponse();
        }
        
        // Fallback scripted questions (must match questionSequence exactly)
        List<String> fallbackQuestions = new List<String>{
            'Hi! I\'m Blakeney, your personal career agent. I\'m here to help you discover opportunities. Ready to get started?',  // 0
            'Got it! What are you hoping to achieve in your career over the next 6 months?',  // 1
            'Perfect! Where do you see yourself in 2-5 years?',  // 2
            'Sounds good! What\'s your long-term career aspiration? Where do you see yourself in 10+ years?',  // 3
            'Excellent! If you could have any job in the world, what would your absolute dream role be?',  // 4
            'Great! Where would you like to work? Are you open to relocating?',  // 5
            'Perfect! What\'s your preference for remote work?',  // 6
            'Got it! What\'s the minimum salary you\'d consider for your next role?',  // 7
            'Sounds good! What\'s your maximum salary expectation?',  // 8
            'Perfect! What size company do you prefer working for?',  // 9
            'Excellent! What industries are you most interested in?',  // 10
            'Great! What is your current role in your company?',  // 11
            'Got it! What tools, technologies, or software have you worked with? Add your technical and professional skills.'  // 12
        };
        
        if (questionsAsked >= 0 && questionsAsked < fallbackQuestions.size()) {
            aiResp.content = fallbackQuestions[questionsAsked];
            System.debug('📋 FALLBACK QUESTION [' + questionsAsked + ']: ' + aiResp.content);
        } else {
            // Shouldn't reach here due to check above, but just in case
            return generateCompletionResponse();
        }
        
        // Detect input settings for the fallback response
        detectInputSettings(aiResp);
        
        return aiResp;
    }
    
    // ============ MAIN AUTO-DETECTION LOGIC ============
    private static void detectInputSettings(AIResponse aiResp) {
        String content = aiResp.content;
        if (String.isBlank(content)) {
            setDefaultInputSettings(aiResp);
            return;
        }
        
        // Step 1: Try to extract bullet point options (- option1, - option2)
        List<String> bulletOptions = extractBulletOptions(content);
        if (!bulletOptions.isEmpty()) {
            aiResp.inputActive = false;
            aiResp.inputType = INPUT_NONE;
            aiResp.inputPlaceholder = 'Select an option above';
            aiResp.quickReplies = createQuickRepliesFromOptions(bulletOptions);
            return;
        }
        
        // Step 2: Try to extract inline options (option1, option2, or option3?)
        List<String> inlineOptions = extractInlineOptions(content);
        if (!inlineOptions.isEmpty()) {
            aiResp.inputActive = true;
            aiResp.inputType = INPUT_TEXT;
            aiResp.inputPlaceholder = 'Type your answer or select above...';
            aiResp.quickReplies = createQuickRepliesFromOptions(inlineOptions);
            return;
        }
        
        // Step 3: Check for known question patterns
        String lowerContent = content.toLowerCase();
        
        // Number questions (salary, years, etc.)
        if (isNumberQuestion(lowerContent)) {
            aiResp.inputActive = true;
            aiResp.inputType = INPUT_NUMBER;
            aiResp.inputPlaceholder = getNumberPlaceholder(lowerContent);
            aiResp.quickReplies = getSalaryQuickReplies(lowerContent);
            return;
        }
        
        // Date questions
        if (isDateQuestion(lowerContent)) {
            aiResp.inputActive = true;
            aiResp.inputType = INPUT_DATE;
            aiResp.inputPlaceholder = 'Select a date...';
            aiResp.quickReplies = getDateReplies();
            return;
        }
        
        // Relocation questions
        if (isRelocationQuestion(lowerContent)) {
            aiResp.inputActive = true;
            aiResp.inputType = INPUT_TEXT;
            aiResp.inputPlaceholder = 'Type your answer or select above...';
            aiResp.quickReplies = getRelocationReplies();
            return;
        }
        
        if(isRemotePreferenceQuestion(lowerContent)){
            aiResp.inputActive = true;
            aiResp.inputType = INPUT_TEXT;
            aiResp.inputPlaceholder = 'Type your answer or select above...';
            aiResp.quickReplies = getRemoteworkPreferenceReplies();
            return;            
        }
        
        if(isCompanySizePreferenceQuestion(lowerContent)){
            aiResp.inputActive = true;
            aiResp.inputType = INPUT_TEXT;
            aiResp.inputPlaceholder = 'Type your answer or select above...';
            aiResp.quickReplies = getCompanySizeReplies();
            return;            
        }
        
        // Default: text input with no quick replies
        setDefaultInputSettings(aiResp);
    }
    
    // ============ EXTRACT BULLET OPTIONS ============
    private static List<String> extractBulletOptions(String content) {
        List<String> options = new List<String>();
        
        List<String> lines = content.split('\n');
        for (String line : lines) {
            String trimmed = line.trim();
            if (trimmed.startsWith('- ') || trimmed.startsWith('* ') || trimmed.startsWith('• ')) {
                String option = trimmed.substring(2).trim();
                option = cleanOption(option);
                if (String.isNotBlank(option) && option.length() > 2 && option.length() < 100) {
                    options.add(option);
                }
            }
        }
        
        // Only return if we have 2-6 valid options
        if (options.size() >= 2 && options.size() <= 6) {
            return options;
        }
        return new List<String>();
    }
    
    // ============ EXTRACT INLINE OPTIONS ============
    private static List<String> extractInlineOptions(String content) {
        List<String> options = new List<String>();
        
        String lowerContent = content.toLowerCase();
        Integer lastQuestionMark = content.lastIndexOf('?');
        if (lastQuestionMark == -1) return options;
        
        // Look for "option1, option2, or option3?" pattern
        String lastPart = content.substring(Math.max(0, lastQuestionMark - 500), lastQuestionMark + 1);
        if (!lastPart.toLowerCase().contains(' or ')) return options;
        
        // Find where options start
        List<String> questionStarters = new List<String>{
            'prefer', 'like', 'interested in', 'looking for', 'want', 
            'choose', 'select', 'pick', 'go with'
        };
        
        Integer optionsStart = -1;
        String lowerLastPart = lastPart.toLowerCase();
        
        for (String starter : questionStarters) {
            Integer idx = lowerLastPart.lastIndexOf(starter);
            if (idx != -1) {
                optionsStart = idx + starter.length();
                break;
            }
        }
        
        // Look for colon as alternative
        Integer colonIdx = lastPart.lastIndexOf(':');
        if (colonIdx != -1 && (optionsStart == -1 || colonIdx > optionsStart)) {
            optionsStart = colonIdx + 1;
        }
        
        if (optionsStart == -1) return options;
        
        // Extract and parse options
        String optionsStr = lastPart.substring(optionsStart, lastPart.length() - 1).trim();
        optionsStr = optionsStr.replace(', or ', ', ');
        optionsStr = optionsStr.replace(' or ', ', ');
        
        List<String> parts = optionsStr.split(',');
        for (String part : parts) {
            String cleaned = cleanOption(part.trim());
            if (String.isNotBlank(cleaned) && cleaned.length() > 2 && cleaned.length() < 80) {
                options.add(cleaned);
            }
        }
        
        // Only return if we have 2-5 valid options
        if (options.size() >= 2 && options.size() <= 5) {
            return options;
        }
        return new List<String>();
    }
    
    // ============ CLEAN OPTION TEXT ============
    private static String cleanOption(String option) {
        if (String.isBlank(option)) return '';
        
        String cleaned = option.trim();
        
        // Remove quotes
        if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
            cleaned = cleaned.substring(1, cleaned.length() - 1);
        }
        
        // Remove markdown bold
        cleaned = cleaned.replace('**', '');
        
        // Remove trailing punctuation
        while (cleaned.length() > 0 && (cleaned.endsWith('.') || cleaned.endsWith(',') || cleaned.endsWith('?'))) {
            cleaned = cleaned.substring(0, cleaned.length() - 1);
        }
        
        // Capitalize first letter
        if (cleaned.length() > 0) {
            cleaned = cleaned.substring(0, 1).toUpperCase() + cleaned.substring(1);
        }
        
        return cleaned.trim();
    }
    
    // ============ CREATE QUICK REPLIES FROM EXTRACTED OPTIONS ============
    private static List<BlakeneyChatService.QuickReply> createQuickRepliesFromOptions(List<String> options) {
        List<BlakeneyChatService.QuickReply> replies = new List<BlakeneyChatService.QuickReply>();
        
        for (Integer i = 0; i < options.size(); i++) {
            String option = options[i];
            
            // Create safe value (no special chars)
            String value = option.toLowerCase()
                .replaceAll('[^a-z0-9\\s]', '')
                .replaceAll('\\s+', '_')
                .substring(0, Math.min(50, option.length()));
            
            // Truncate long labels
            String label = option.length() > 40 ? option.substring(0, 37) + '...' : option;
            
            BlakeneyChatService.QuickReply qr = new BlakeneyChatService.QuickReply();
            qr.label = label;
            qr.value = value;
            qr.action = 'select';
            qr.isPrimary = (i == 0);
            replies.add(qr);
        }
        
        return replies;
    }
    
    // ============ NUMBER DETECTION ============
    private static Boolean isNumberQuestion(String content) {
        List<String> patterns = new List<String>{
            'salary', 'expected salary', 'minimum salary', 'maximum salary',
            'how many years', 'years of experience', 'hours per week', 
            'percentage', 'budget', 'compensation', 'pay'
        };
        for (String p : patterns) {
            if (content.contains(p)) return true;
        }
        return false;
    }
    
    private static String getNumberPlaceholder(String content) {
        if (content.contains('salary') || content.contains('compensation') || content.contains('pay')) {
            return 'Enter salary amount...';
        }
        if (content.contains('years')) return 'Enter number of years...';
        if (content.contains('hours')) return 'Enter hours per week...';
        return 'Enter a number...';
    }
    
    private static List<BlakeneyChatService.QuickReply> getSalaryQuickReplies(String content) {
        List<BlakeneyChatService.QuickReply> replies = new List<BlakeneyChatService.QuickReply>();
        
        if (content.contains('minimum')) {
            replies.add(createQuickReply('$50,000', '50000', true));
            replies.add(createQuickReply('$75,000', '75000', false));
            replies.add(createQuickReply('$100,000', '100000', false));
            replies.add(createQuickReply('$150,000+', '150000', false));
        } else if (content.contains('maximum') || content.contains('target')) {
            replies.add(createQuickReply('$100,000', '100000', true));
            replies.add(createQuickReply('$150,000', '150000', false));
            replies.add(createQuickReply('$200,000', '200000', false));
            replies.add(createQuickReply('$250,000+', '250000', false));
        }
        
        return replies;
    }
    
    // ============ DATE DETECTION ============
    private static Boolean isDateQuestion(String content) {
        List<String> patterns = new List<String>{
            'when can you start', 'start date', 'available from', 
            'notice period', 'availability'
        };
        for (String p : patterns) {
            if (content.contains(p)) return true;
        }
        return false;
    }
    
    private static List<BlakeneyChatService.QuickReply> getDateReplies() {
        List<BlakeneyChatService.QuickReply> replies = new List<BlakeneyChatService.QuickReply>();
        replies.add(createQuickReply('Immediately', 'immediate', true));
        replies.add(createQuickReply('2 weeks', '2_weeks', false));
        replies.add(createQuickReply('1 month', '1_month', false));
        replies.add(createQuickReply('Flexible', 'flexible', false));
        return replies;
    }
    
    private static List<BlakeneyChatService.QuickReply> getCompanySizeReplies() {
        List<BlakeneyChatService.QuickReply> replies = new List<BlakeneyChatService.QuickReply>();
        replies.add(createQuickReply('Startup (1-50)', 'Startup (1-50)', true));
        replies.add(createQuickReply('Small (51-200)', 'Small (51-200)', false));
        replies.add(createQuickReply('Medium (201-1000)', 'Medium (201-1000)', false));
        replies.add(createQuickReply('Large (1001-5000)', 'Large (1001-5000)', false));
        replies.add(createQuickReply('Enterprise (5000+)', 'Enterprise (5000+)', false));
        return replies;
    }
    
    private static Boolean isCompanySizePreferenceQuestion(String content) {
        List<String> patterns = new List<String>{
            'size company', 'company size'
        };
        for (String p : patterns) {
            if (content.contains(p)) return true;
        }
        return false;
    }
    
    private static Boolean isRemotePreferenceQuestion(String content) {
        List<String> patterns = new List<String>{
            'remote', 'remote work'
        };
        for (String p : patterns) {
            if (content.contains(p)) return true;
        }
        return false;
    }
    
    private static Boolean isRelocationQuestion(String content) {
        List<String> patterns = new List<String>{
            'relocat', 'open to relocat', 'willing to relocat', 
            'move to', 'willing to move', 'open to moving',
            'prefer to stay', 'current area'
        };
        for (String p : patterns) {
            if (content.contains(p)) return true;
        }
        return false;
    }
    
    private static List<BlakeneyChatService.QuickReply> getRelocationReplies() {
        List<BlakeneyChatService.QuickReply> replies = new List<BlakeneyChatService.QuickReply>();
        replies.add(createQuickReply('Yes', 'yes', true));
        replies.add(createQuickReply('No', 'no', false));
        replies.add(createQuickReply('Maybe', 'maybe', false));
        return replies;
    }
    
    private static List<BlakeneyChatService.QuickReply> getRemoteworkPreferenceReplies() {
        List<BlakeneyChatService.QuickReply> replies = new List<BlakeneyChatService.QuickReply>();
        replies.add(createQuickReply('Remote Only', 'Remote Only', true));
        replies.add(createQuickReply('Hybrid', 'Hybrid', false));
        replies.add(createQuickReply('On-Site', 'On-Site', false));
        replies.add(createQuickReply('Flexible', 'Flexible', false));
        return replies;
    }
    
    // ============ DEFAULT SETTINGS ============
    private static void setDefaultInputSettings(AIResponse aiResp) {
        aiResp.inputActive = true;
        aiResp.inputType = INPUT_TEXT;
        aiResp.inputPlaceholder = 'Type your message...';
        aiResp.quickReplies = new List<BlakeneyChatService.QuickReply>();
    }
    
    private static BlakeneyChatService.QuickReply createQuickReply(String label, String value, Boolean isPrimary) {
        BlakeneyChatService.QuickReply qr = new BlakeneyChatService.QuickReply();
        qr.label = label;
        qr.value = value;
        qr.action = 'select';
        qr.isPrimary = isPrimary;
        return qr;
    }
    
    private static String getAPIKey() {
        try {
            Blakeney_Setting__mdt settings = [
                SELECT Claude_API_Key__c 
                FROM Blakeney_Setting__mdt 
                WHERE DeveloperName = 'Default' 
                LIMIT 1
            ];
            return settings != null ? settings.Claude_API_Key__c : '';
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to get API key: ' + e.getMessage());
            return '';
        }
    }
    
    public class AIResponse {
        public String content;
        public String model;
        public Integer inputTokens;
        public Integer outputTokens;
        public Integer totalTokens;
        public String error;
        public List<BlakeneyChatService.QuickReply> quickReplies;
        public Boolean inputActive;
        public String inputType;
        public String inputPlaceholder;
        
        public AIResponse() {
            this.quickReplies = new List<BlakeneyChatService.QuickReply>();
            this.inputActive = true;
            this.inputType = INPUT_TEXT;
            this.inputPlaceholder = 'Type your message...';
        }
    }
}