/**
 * ClaudeAPIService - FIXED VERSION
 * Claude API integration with job extraction
 */
public with sharing class ClaudeAPIService {
    
    private static final String API_ENDPOINT = 'https://api.anthropic.com/v1/messages';
    private static final String API_VERSION = '2023-06-01';
    private static final String DEFAULT_MODEL = 'claude-sonnet-4-20250514';

    /**
     * Generic Claude chat API used by FlintChatController.
     */
    public static ClaudeResponse chat(
        String systemPrompt,
        List<Map<String, String>> messages,
        Decimal temperature,
        Integer maxTokens
    ) {
        HttpResponse response = callClaudeAPI(systemPrompt, messages, temperature, maxTokens);
        return parseResponse(response, '0');
    }

    /**
     * Generic structured extraction helper used by Flint helpers/controllers.
     * Returns parsed JSON object, or empty map on API/parse failure.
     */
    public static Map<String, Object> extractStructuredData(String sourceText, String extractionPrompt) {
        try {
            String prompt = String.isBlank(extractionPrompt)
                ? 'Extract structured data from this text. Return ONLY valid JSON.'
                : extractionPrompt;

            List<Map<String, String>> messages = new List<Map<String, String>>{
                new Map<String, String>{
                    'role' => 'user',
                    'content' => prompt + '\n\nTEXT:\n' + (sourceText == null ? '' : sourceText)
                }
            };

            ClaudeResponse response = chat(
                'You are a structured data extraction assistant. Return ONLY valid JSON. No markdown. No explanation.',
                messages,
                0.1,
                1000
            );

            if (String.isBlank(response.content)) {
                return new Map<String, Object>();
            }

            String cleaned = cleanJsonResponse(response.content);
            Object parsed = JSON.deserializeUntyped(cleaned);
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>) parsed;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Structured extraction failed: ' + e.getMessage());
        }
        return new Map<String, Object>();
    }
    
    /**
     * Generate job response from Claude
     * Includes job detail extraction for Job_Intake conversations
     */
    public static ClaudeResponse generateJobResponse(
        String userMessage,
        FlintChatService.ChatContext ctx,
        String conversationType,
        String questionCount) {
        
        System.debug('═══════════════════════════════════════════════════════');
        System.debug('🎯 ClaudeAPIService.generateJobResponse');
        System.debug('   Question: ' + questionCount);
        System.debug('   Conversation Type: ' + conversationType);
        System.debug('═══════════════════════════════════════════════════════');
        
        Integer qNum = 0;
        try {
            qNum = Integer.valueOf(questionCount);
        } catch (Exception e) {
            qNum = 0;
        }
        
        // Check if conversation is complete
        if (FlintJobSequence.isComplete(qNum)) {
            System.debug('✅ All questions complete - returning completion');
            return generateCompletionResponse();
        }
        
        // Build system prompt
        String systemPrompt = buildJobIntakeSystemPrompt(qNum);
        
        // Build message history
        List<Map<String, String>> messages = buildMessageHistory(ctx, userMessage);
        
        // Get exact question to ask
        String exactQuestion = FlintJobSequence.getQuestion(qNum);
        
        // Call Claude API with prefill
        HttpResponse response = callClaudeAPIWithPrefill(
            systemPrompt, messages, exactQuestion, 0.1, 1024
        );
        
        System.debug('Claude Response Status: ' + response.getStatusCode());
            System.debug('Claude Response Status: ' + response.getBody());
        
        // Parse response
        ClaudeResponse result = parseResponse(response, questionCount);
        
        // ✅ NEW: Extract job details if this is Job_Intake
        if (conversationType == 'Job_Intake') {
            try {
                System.debug('🔍 Extracting job details from conversation...');
                result.extractedData = extractJobDetailsFromMessages(messages);
                System.debug('✅ Extracted job details: ' + result.extractedData.keySet());
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Could not extract job details: ' + e.getMessage());
                result.extractedData = new Map<String, Object>();
            }
        }
        
        // Check for off-script responses
        if (result.error != null && result.error.contains('OFF_SCRIPT')) {
            System.debug('⚠️ Off-script detected - using fallback');
            result = generateFallbackResponse(questionCount);
        }
        
        System.debug('✅ Response ready');
        System.debug('═══════════════════════════════════════════════════════');
        
        return result;
    }
    
    /**
     * Extract structured job data from conversation messages
     * ✅ NEW METHOD - Extracts job details from all messages
     */
    public static Map<String, Object> extractJobDetailsFromMessages(
        List<Map<String, String>> messages) {
        
        System.debug('🔍 Extracting job details from conversation messages...');
        
        try {
            // Build conversation text from messages
            String conversation = '';
            for (Map<String, String> msg : messages) {
                String role = msg.get('role');
                String content = msg.get('content');
                conversation += role.toUpperCase() + ': ' + content + '\n\n';
            }
            
            String extractionPrompt = 'Extract the following job details from this conversation if mentioned. Return ONLY valid JSON with no markdown formatting:\n' +
                '{\n' +
                '  "job_title": "The job title or null",\n' +
                '  "seniority_level": "Junior/Mid/Senior/Lead/Executive or null",\n' +
                '  "must_have_skills": ["skill1", "skill2"] or null,\n' +
                '  "nice_to_have_skills": ["skill1", "skill2"] or null,\n' +
                '  "salary_min": number or null,\n' +
                '  "salary_max": number or null,\n' +
                '  "timeline_days": number or null,\n' +
                '  "work_arrangement": "Onsite/Hybrid/Remote or null",\n' +
                '  "location": "Job location or null",\n' +  //Test
				'  "Employment_Type": " permanent, contract, or temporary",\n' +
                '  "culture_notes": "Team fit notes or null"\n' +
                '}\n\n' +
                'Set unmentioned fields to null. Return ONLY the JSON object.\n\n' +
                'CONVERSATION:\n' + conversation;
            
            // Create extraction request
            Map<String, Object> requestBody = new Map<String, Object>{
                'model' => DEFAULT_MODEL,
                'max_tokens' => 1000,
                'temperature' => 0.1,
                'system' => 'You are a data extraction assistant. Extract the requested information and return ONLY valid JSON with no explanation or markdown formatting.',
                'messages' => new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'role' => 'user',
                        'content' => extractionPrompt
                    }
                }
            };
            
            // Make HTTP request
            HttpRequest req = new HttpRequest();
            req.setEndpoint(API_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('x-api-key', getAPIKey());
            req.setHeader('anthropic-version', API_VERSION);
            req.setBody(JSON.serialize(requestBody));
            req.setTimeout(60000);
            
            Http http = new Http();
            Long started = DateTime.now().getTime();
            HttpResponse res;
            try {
                res = http.send(req);
            } catch (Exception calloutException) {
                logHttpFailure('Job Detail Extraction', req.getBody(), calloutException.getMessage(), started);
                throw calloutException;
            }
            logHttpCall('Job Detail Extraction', req.getBody(), res, started);
            
            if (res.getStatusCode() != 200) {
                System.debug(LoggingLevel.ERROR, 'Extraction API error: ' + res.getStatusCode());
                return new Map<String, Object>();
            }
            
            // Parse extraction response
            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> content = (List<Object>) responseBody.get('content');
            
            if (content == null || content.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'No content in extraction response');
                return new Map<String, Object>();
            }
            
            Map<String, Object> textBlock = (Map<String, Object>) content[0];
            String extractedJson = (String) textBlock.get('text');
            
            System.debug('📊 Raw extracted JSON: ' + extractedJson);
            
            // Clean up the response (remove markdown if present)
            String cleaned = extractedJson.trim();
            if (cleaned.startsWith('```json')) {
                cleaned = cleaned.replace('```json', '').trim();
            }
            if (cleaned.startsWith('```')) {
                cleaned = cleaned.replace('```', '').trim();
            }
            if (cleaned.endsWith('```')) {
                cleaned = cleaned.substring(0, cleaned.length() - 3).trim();
            }
            
            Map<String, Object> extracted = (Map<String, Object>) JSON.deserializeUntyped(cleaned);
            System.debug('✅ Successfully extracted job details with keys: ' + extracted.keySet());
            
            return extracted;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Job detail extraction failed: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            return new Map<String, Object>();
        }
    }
    
    /**
     * Build system prompt for job intake
     */
    private static String buildJobIntakeSystemPrompt(Integer questionNum) {
        String basePrompt = 'You are Flint, an AI recruitment consultant for ReZourcer.ai. ' +
            'You are professional, friendly, and data-driven. Your job is to help employers ' +
            'create compelling job postings through conversation.\n\n' +
            'CRITICAL RULES:\n' +
            '1. Ask ONLY the exact question provided below\n' +
            '2. Keep your response to 2 sentences maximum\n' +
            '3. Format: Brief acknowledgment + the exact question\n' +
            '4. Do NOT create your own questions\n' +
            '5. Do NOT deviate from the script\n\n' +
            'Example: "Got it! [EXACT QUESTION HERE]"\n\n';
        
        String questionContext = 'NEXT QUESTION TO ASK:\n' +
            'Q' + questionNum + ': ' + FlintJobSequence.getQuestion(questionNum) + '\n\n' +
            'Use the exact wording above. Do not modify or skip.';
        
        return basePrompt + questionContext;
    }
    
    /**
     * Build message history from recent messages
     */
    private static List<Map<String, String>> buildMessageHistory(
        FlintChatService.ChatContext ctx, String currentMessage) {
        
        List<Map<String, String>> messages = new List<Map<String, String>>();
        
        // Add recent messages from context
        if (ctx != null && ctx.recentMessages != null && !ctx.recentMessages.isEmpty()) {
            Boolean hasUserStartedHistory = false;
            for (Chat_Interaction__c msg : ctx.recentMessages) {
                String role = msg.Message_Type__c == 'User' ? 'user' : 'assistant';
                if (!hasUserStartedHistory && role == 'assistant') {
                    continue;
                }
                if (role == 'user') {
                    hasUserStartedHistory = true;
                }
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
    
    /**
     * Call Claude API with prefill
     */
    private static HttpResponse callClaudeAPIWithPrefill(
        String systemPrompt,
        List<Map<String, String>> messages,
        String exactQuestion,
        Decimal temperature,
        Integer maxTokens) {
        
        String prefill = 'Got it!';
        
        // Add prefill to messages
        messages.add(new Map<String, String>{
            'role' => 'assistant',
            'content' => prefill
        });
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(API_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-api-key', getAPIKey());
        req.setHeader('anthropic-version', API_VERSION);
        req.setTimeout(60000);
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'model' => DEFAULT_MODEL,
            'max_tokens' => maxTokens,
            'temperature' => temperature,
            'system' => systemPrompt,
            'messages' => messages
        };
        
        req.setBody(JSON.serialize(requestBody));
        
        System.debug('Calling Claude API with prefill...');
        
        Http http = new Http();
        Long started = DateTime.now().getTime();
        try {
            HttpResponse res = http.send(req);
            logHttpCall('Flint Job Intake', req.getBody(), res, started);
            return res;
        } catch (Exception calloutException) {
            logHttpFailure('Flint Job Intake', req.getBody(), calloutException.getMessage(), started);
            throw calloutException;
        }
    }

    private static HttpResponse callClaudeAPI(
        String systemPrompt,
        List<Map<String, String>> messages,
        Decimal temperature,
        Integer maxTokens
    ) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(API_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-api-key', getAPIKey());
        req.setHeader('anthropic-version', API_VERSION);
        req.setTimeout(60000);

        List<Map<String, Object>> apiMessages = new List<Map<String, Object>>();
        if (messages != null) {
            for (Map<String, String> msg : messages) {
                if (msg == null || String.isBlank(msg.get('content'))) continue;
                String role = msg.get('role') == 'assistant' ? 'assistant' : 'user';
                apiMessages.add(new Map<String, Object>{
                    'role' => role,
                    'content' => msg.get('content')
                });
            }
        }
        if (apiMessages.isEmpty()) {
            apiMessages.add(new Map<String, Object>{
                'role' => 'user',
                'content' => ''
            });
        }

        Map<String, Object> requestBody = new Map<String, Object>{
            'model' => DEFAULT_MODEL,
            'max_tokens' => maxTokens == null ? 1024 : maxTokens,
            'temperature' => temperature == null ? 0.3 : temperature,
            'system' => String.isBlank(systemPrompt) ? 'You are Flint, an AI recruitment assistant.' : systemPrompt,
            'messages' => apiMessages
        };

        req.setBody(JSON.serialize(requestBody));

        Http http = new Http();
        Long started = DateTime.now().getTime();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (Exception calloutException) {
            logHttpFailure('Chat Completion', req.getBody(), calloutException.getMessage(), started);
            throw calloutException;
        }
        logHttpCall('Chat Completion', req.getBody(), res, started);
        return res;
    }
    
    /**
     * Parse Claude API response
     */
    private static ClaudeResponse parseResponse(HttpResponse response, String questionCount) {
        ClaudeResponse result = new ClaudeResponse();
        
        if (response.getStatusCode() == 200) {
            try {
                Map<String, Object> respBody = (Map<String, Object>) JSON.deserializeUntyped(
                    response.getBody()
                );
                
                // Extract text content
                List<Object> content = (List<Object>) respBody.get('content');
                if (content != null && !content.isEmpty()) {
                    Map<String, Object> textBlock = (Map<String, Object>) content[0];
                    String claudeResponse = (String) textBlock.get('text');
                    result.content = claudeResponse;
                }
                
                // Extract token usage
                Map<String, Object> usage = (Map<String, Object>) respBody.get('usage');
                if (usage != null) {
                    result.inputTokens = (Integer) usage.get('input_tokens');
                    result.outputTokens = (Integer) usage.get('output_tokens');
                    result.totalTokens = result.inputTokens + result.outputTokens;
                    result.tokensUsed = result.totalTokens;
                }
                
                // Check for forbidden keywords (off-script detection)
                if (containsForbiddenKeywords(result.content)) {
                    System.debug(LoggingLevel.WARN, '⚠️ Forbidden keywords detected');
                    result.error = 'OFF_SCRIPT_RESPONSE_DETECTED';
                }
                
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Error parsing response: ' + e.getMessage());
                result.error = 'PARSE_ERROR';
                result.content = 'I apologize, but I had trouble processing the response. Please try again.';
            }
            
        } else {
            System.debug(LoggingLevel.ERROR, 'Claude API Error: ' + response.getStatusCode());
            result.content = 'I apologize, but I\'m having trouble connecting. Please try again.';
            result.error = 'API Error: ' + response.getStatusCode();
            result.tokensUsed = 0;
        }
        
        return result;
    }

    private static String cleanJsonResponse(String raw) {
        String cleaned = raw == null ? '' : raw.trim();
        if (cleaned.startsWith('```json')) {
            cleaned = cleaned.replace('```json', '').trim();
        }
        if (cleaned.startsWith('```')) {
            cleaned = cleaned.replace('```', '').trim();
        }
        if (cleaned.endsWith('```')) {
            cleaned = cleaned.substring(0, cleaned.length() - 3).trim();
        }

        Integer startIndex = cleaned.indexOf('{');
        Integer endIndex = cleaned.lastIndexOf('}');
        if (startIndex >= 0 && endIndex > startIndex) {
            cleaned = cleaned.substring(startIndex, endIndex + 1);
        }
        return cleaned;
    }

    private static void logHttpCall(String operation, String requestPayload, HttpResponse response, Long started) {
        try {
            AIAPILogService.LogEntry entry = new AIAPILogService.LogEntry();
            entry.operation = operation;
            entry.requestType = AIAPILogService.requestTypeForOperation(operation);
            entry.requestPayload = requestPayload;
            entry.responsePayload = response == null ? null : response.getBody();
            entry.status = response != null && response.getStatusCode() >= 200 && response.getStatusCode() < 300 ? 'Success' : 'Failed';
            entry.errorMessage = entry.status == 'Failed' && response != null ? 'Claude API HTTP ' + response.getStatusCode() : null;
            entry.model = DEFAULT_MODEL;
            entry.durationMs = Integer.valueOf(String.valueOf(DateTime.now().getTime() - started));
            entry.httpStatusCode = response == null ? null : response.getStatusCode();
            if (response != null && String.isNotBlank(response.getBody()) && response.getStatusCode() == 200) {
                Map<String, Object> respBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                Map<String, Object> usage = (Map<String, Object>) respBody.get('usage');
                if (usage != null) {
                    entry.inputTokens = integerValue(usage.get('input_tokens'));
                    entry.outputTokens = integerValue(usage.get('output_tokens'));
                    entry.totalTokens = (entry.inputTokens == null ? 0 : entry.inputTokens) + (entry.outputTokens == null ? 0 : entry.outputTokens);
                }
            }
            AIAPILogService.logClaudeCall(entry);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Claude API log skipped: ' + e.getMessage());
        }
    }

    private static void logHttpFailure(String operation, String requestPayload, String errorMessage, Long started) {
        try {
            AIAPILogService.LogEntry entry = new AIAPILogService.LogEntry();
            entry.operation = operation;
            entry.requestType = AIAPILogService.requestTypeForOperation(operation);
            entry.requestPayload = requestPayload;
            entry.status = 'Failed';
            entry.errorMessage = errorMessage;
            entry.model = DEFAULT_MODEL;
            entry.durationMs = Integer.valueOf(String.valueOf(DateTime.now().getTime() - started));
            AIAPILogService.logClaudeCall(entry);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Claude API failure log skipped: ' + e.getMessage());
        }
    }

    private static Integer integerValue(Object value) {
        if (value == null) return null;
        try {
            return Integer.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * Check for forbidden keywords (off-script detection)
     */
    private static Boolean containsForbiddenKeywords(String response) {
        if (String.isBlank(response)) return false;
        
        String lower = response.toLowerCase();
        List<String> forbidden = new List<String>{
            'tell me about yourself', 'what are your strengths', 'weakness',
            'past experience', 'how do you handle conflict', 'team player'
        };
        
        for (String keyword : forbidden) {
            if (lower.contains(keyword)) {
                System.debug('🚫 Forbidden: ' + keyword);
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * Generate completion response
     */
    private static ClaudeResponse generateCompletionResponse() {
        ClaudeResponse result = new ClaudeResponse();
        result.content = 'Congratulations! 🎉 Your job posting is complete. ' +
            'You can now publish it or make any final edits.';
        result.inputTokens = 0;
        result.outputTokens = 0;
        result.totalTokens = 0;
        result.tokensUsed = 0;
        result.extractedData = new Map<String, Object>();
        return result;
    }
    
    /**
     * Generate fallback response when Claude goes off-script
     */
    public static ClaudeResponse generateFallbackResponse(String questionCount) {
        ClaudeResponse result = new ClaudeResponse();
        
        Integer qNum = 0;
        try {
            qNum = Integer.valueOf(questionCount);
        } catch (Exception e) {
            qNum = 0;
        }
        
        // Check if all questions are complete
        if (qNum >= FlintJobSequence.JOB_INTAKE_QUESTIONS.size()) {
            return generateCompletionResponse();
        }
        
        // Use varied prefixes for natural feel
        List<String> prefixes = new List<String>{
            'Got it!', 'Perfect!', 'Thanks!', 'Understood!', 'Great!'
        };
        
        String prefix = prefixes[Math.mod(qNum, prefixes.size())];
        result.content = prefix + ' ' + FlintJobSequence.getQuestion(qNum);
        result.inputTokens = 0;
        result.outputTokens = 0;
        result.totalTokens = 0;
        result.tokensUsed = 0;
        result.extractedData = new Map<String, Object>();
        
        return result;
    }
    
    /**
     * Get Claude API key from custom metadata
     */
    private static String getAPIKey() {
        try {
            Blakeney_Setting__mdt settings = [
                SELECT Claude_API_Key__c 
                FROM Blakeney_Setting__mdt 
                WHERE DeveloperName = 'Default' 
                LIMIT 1
            ];
            
            if (settings != null && String.isNotBlank(settings.Claude_API_Key__c)) {
                return settings.Claude_API_Key__c;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to get API key: ' + e.getMessage());
        }
        
        throw new ClaudeAPIException('Claude API key not configured in Blakeney_Setting__mdt');
    }
    
    // ==================== RESPONSE CLASS ====================
    
    public class ClaudeResponse {
        public String content;
        public String model = 'claude-sonnet-4-20250514';
        public Integer inputTokens;
        public Integer outputTokens;
        public Integer totalTokens;
        public Integer tokensUsed;
        public String error;
        public Map<String, Object> extractedData = new Map<String, Object>();
    }
    
    public class ClaudeAPIException extends Exception {}
}
