/**
 * FlintChatController
 * Handles Flint AI conversation logic for employer portal
 */
public with sharing class FlintChatController {
    
    @AuraEnabled
    public static Chat_Interaction__c startConversation(Id accountId, String conversationType) {
        // Validate feature access
        SubscriptionService.validateFeatureAccess(accountId, 'Flint_Conversations');
        
        // Get current user
        Id userId = UserInfo.getUserId();
        List<Contact> contacts = [SELECT Id FROM Contact WHERE User__c = :userId AND AccountId = :accountId LIMIT 1];
        Id contactId = contacts.isEmpty() ? null : contacts[0].Id;
        
        Chat_Interaction__c interaction = new Chat_Interaction__c(
            Account__c = accountId,
            Contact__c = contactId,
            Conversation_Type__c = conversationType,
            Status__c = 'Active',
            Started_At__c = DateTime.now(),
            Session_ID__c = generateSessionId(),
            AI_Model__c = 'claude-opus-4-6',
            Message_Count__c = 0
        );
        
        insert interaction;
        
        // Add Flint greeting
        String greeting = getFlintGreeting(accountId, conversationType);
        addMessage(interaction.Id, 'Assistant', greeting, null);
        
        return interaction;
    }
    
    @AuraEnabled
    public static FlintResponse sendMessage(Id interactionId, String userMessage) {
        Chat_Interaction__c interaction = [
            SELECT Id, Account__c, Contact__c, Conversation_Type__c, Message_Count__c
            FROM Chat_Interaction__c 
            WHERE Id = :interactionId
        ];
        
        // Add user message
        addMessage(interactionId, 'User', userMessage, null);
        
        // Build conversation history
        List<Map<String,String>> messages = buildConversationHistory(interactionId);
        
        // Get prompt template
        String systemPrompt = getSystemPrompt(interaction.Conversation_Type__c);
        
        // Call Claude AI
        ClaudeAPIService.ClaudeResponse aiResponse = ClaudeAPIService.chat(
            systemPrompt, messages, 0.7, 1024
        );
        
        // Extract job details if job intake
        Map<String,Object> extractedData = new Map<String,Object>();
        if (interaction.Conversation_Type__c == 'Job_Intake') {
            extractedData = extractJobDetails(interactionId);
        }
        
        // Add AI response
        addMessage(interactionId, 'Assistant', aiResponse.content, JSON.serialize(extractedData));
        
        // Update metrics
        interaction.Message_Count__c = interaction.Message_Count__c + 2;
        interaction.Total_Tokens__c = (interaction.Total_Tokens__c == null ? 0 : interaction.Total_Tokens__c) + aiResponse.tokensUsed;
        update interaction;
        
        return new FlintResponse(
            aiResponse.content,
            extractedData,
            getSuggestedResponses(interaction.Conversation_Type__c, extractedData)
        );
    }
    
    @AuraEnabled
    public static Id completeConversation(Id interactionId, Map<String,Object> jobDetails) {
        Chat_Interaction__c interaction = [
            SELECT Id, Account__c, Conversation_Type__c
            FROM Chat_Interaction__c 
            WHERE Id = :interactionId
        ];
        
        Id campaignId = null;
        
        if (interaction.Conversation_Type__c == 'Job_Intake' && jobDetails != null && !jobDetails.isEmpty()) {
            campaignId = JobCampaignService.createFromFlint(interaction.Account__c, jobDetails);
            interaction.Related_Campaign__c = campaignId;
            interaction.Outcome__c = 'Job_Created';
        } else {
            interaction.Outcome__c = 'No_Action';
        }
        
        interaction.Status__c = 'Completed';
        interaction.Ended_At__c = DateTime.now();
        interaction.Conversation_Summary__c = generateConversationSummary(interactionId);
        
        update interaction;
        
        return campaignId;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Chat_Interaction__c> getRecentConversations(Id accountId, Integer limitCount) {
        return [
            SELECT Id, Name, Conversation_Type__c, Status__c, Started_At__c, 
                   Ended_At__c, Outcome__c, Conversation_Summary__c, Related_Campaign__c
            FROM Chat_Interaction__c
            WHERE Account__c = :accountId
            ORDER BY Started_At__c DESC
            LIMIT :limitCount
        ];
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Chat_Message__c> getConversationMessages(Id interactionId) {
        return [
            SELECT Id, Role__c, Content__c, Timestamp__c, Sequence_Number__c
            FROM Chat_Message__c
            WHERE Chat_Interaction__c = :interactionId
            ORDER BY Sequence_Number__c ASC
        ];
    }
    
    // Helper methods
    private static void addMessage(Id interactionId, String role, String content, String extractedData) {
        Integer nextSequence = [SELECT COUNT() FROM Chat_Message__c WHERE Chat_Interaction__c = :interactionId];
        
        Chat_Message__c msg = new Chat_Message__c(
            Chat_Interaction__c = interactionId,
            Role__c = role,
            Content__c = content,
            Timestamp__c = DateTime.now(),
            Sequence_Number__c = nextSequence + 1,
            Extracted_Data__c = extractedData
        );
        insert msg;
    }
    
    private static String generateSessionId() {
        return 'FLINT-' + String.valueOf(DateTime.now().getTime()) + '-' + String.valueOf(Math.random()).substring(2, 8);
    }
    
    private static String getFlintGreeting(Id accountId, String conversationType) {
        Account employer = [SELECT Name FROM Account WHERE Id = :accountId];
        String companyName = employer.Name;
        
        if (conversationType == 'Job_Intake') {
            return 'Hi! I\'m Flint, your AI recruitment consultant. I\'m here to help you create a compelling job posting. Tell me about the role you\'re hiring for at ' + companyName + '.';
        } else if (conversationType == 'Onboarding') {
            return 'Welcome to ReZourcer.ai! I\'m Flint, and I\'ll be your AI recruitment partner. Let me learn about ' + companyName + ' and your typical hiring needs so I can help you find the perfect candidates.';
        } else {
            return 'Hi! I\'m Flint, your AI recruitment consultant. How can I help you today?';
        }
    }
    
    private static String getSystemPrompt(String conversationType) {
        String basePrompt = 'You are Flint, an AI recruitment consultant for ReZourcer.ai. You are professional, efficient, and data-driven. You help employers find great candidates.';
        
        if (conversationType == 'Job_Intake') {
            return basePrompt + '\n\nYour task is to gather job requirements through conversation. Ask about:\n1. Job title and seniority level\n2. Must-have vs nice-to-have skills\n3. Salary range (provide market recommendations)\n4. Timeline and urgency\n5. Team culture and fit requirements\n\nAsk one or two questions at a time. Be concise but thorough.';
        } else if (conversationType == 'Onboarding') {
            return basePrompt + '\n\nYour task is to onboard a new employer. Learn about their company, typical roles they hire for, and their hiring challenges. Be welcoming and helpful.';
        }
        return basePrompt;
    }
    
    private static List<Map<String,String>> buildConversationHistory(Id interactionId) {
        List<Chat_Message__c> messages = [
            SELECT Role__c, Content__c 
            FROM Chat_Message__c 
            WHERE Chat_Interaction__c = :interactionId 
            ORDER BY Sequence_Number__c ASC
        ];
        
        List<Map<String,String>> history = new List<Map<String,String>>();
        for (Chat_Message__c msg : messages) {
            history.add(new Map<String,String>{
                'role' => msg.Role__c.toLowerCase(),
                'content' => msg.Content__c
            });
        }
        return history;
    }
    
    private static Map<String,Object> extractJobDetails(Id interactionId) {
        List<Chat_Message__c> messages = [
            SELECT Content__c FROM Chat_Message__c 
            WHERE Chat_Interaction__c = :interactionId 
            ORDER BY Sequence_Number__c ASC
        ];
        
        String fullConversation = '';
        for (Chat_Message__c msg : messages) {
            fullConversation += msg.Content__c + '\n';
        }
        
        String extractionPrompt = 'Extract the following job details from this conversation if mentioned:\n' +
            '- job_title: The job title\n' +
            '- seniority_level: Junior, Mid, Senior, Lead, or Executive\n' +
            '- must_have_skills: Array of required skills\n' +
            '- nice_to_have_skills: Array of preferred skills\n' +
            '- salary_min: Minimum salary as number\n' +
            '- salary_max: Maximum salary as number\n' +
            '- timeline_days: Days to fill position\n' +
            '- work_arrangement: Onsite, Hybrid, or Remote\n' +
            '- location: Job location\n' +
            '- culture_notes: Any culture or team fit notes\n\n' +
            'Return only mentioned fields. Use null for unmentioned fields.';
        
        return ClaudeAPIService.extractStructuredData(fullConversation, extractionPrompt);
    }
    
    private static List<String> getSuggestedResponses(String conversationType, Map<String,Object> extractedData) {
        List<String> suggestions = new List<String>();
        
        if (conversationType == 'Job_Intake') {
            if (extractedData.get('job_title') == null) {
                suggestions.add('Senior Software Engineer');
                suggestions.add('Product Manager');
                suggestions.add('Data Analyst');
            } else if (extractedData.get('must_have_skills') == null) {
                suggestions.add('Let me list the required skills');
                suggestions.add('What skills do you recommend?');
            } else if (extractedData.get('salary_min') == null) {
                suggestions.add('What\'s the market rate?');
                suggestions.add('Our budget is flexible');
            }
        }
        
        return suggestions;
    }
    
    private static String generateConversationSummary(Id interactionId) {
        List<Chat_Message__c> messages = [
            SELECT Role__c, Content__c FROM Chat_Message__c 
            WHERE Chat_Interaction__c = :interactionId 
            ORDER BY Sequence_Number__c ASC
            LIMIT 20
        ];
        
        if (messages.isEmpty()) return 'No messages';
        
        String conversation = '';
        for (Chat_Message__c msg : messages) {
            conversation += msg.Role__c + ': ' + msg.Content__c.left(200) + '\n';
        }
        
        try {
            String prompt = 'Summarize this conversation in 2-3 sentences:\n\n' + conversation;
            ClaudeAPIService.ClaudeResponse response = ClaudeAPIService.chat(
                'You are a summarization assistant. Be concise.',
                new List<Map<String,String>>{ new Map<String,String>{'role' => 'user', 'content' => prompt} },
                0.3, 150
            );
            return response.content;
        } catch (Exception e) {
            return 'Conversation with ' + messages.size() + ' messages';
        }
    }
    
    // Response wrapper class
    public class FlintResponse {
        @AuraEnabled public String message;
        @AuraEnabled public Map<String,Object> extractedData;
        @AuraEnabled public List<String> suggestedResponses;
        
        public FlintResponse(String msg, Map<String,Object> data, List<String> suggestions) {
            this.message = msg;
            this.extractedData = data;
            this.suggestedResponses = suggestions;
        }
    }
}