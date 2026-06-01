/**
 * FlintChatController Helper Methods (additions)
 */
public class FlintChatHelpers {
    
    public static Id getCurrentUserId() {
        return UserInfo.getUserId();
    }
    
    public static String getFlintGreeting(Id accountId, String conversationType) {
        Account employer = [SELECT Name FROM Account WHERE Id = :accountId];
        
        Map<String, String> greetings = new Map<String, String>{
            'Job_Intake' => 'Hi! I\'m Flint, your AI recruiting assistant. I\'ll help you ' +
                'create a job posting for ' + employer.Name + '. Let\'s start with the basics - ' +
                'what position are you looking to fill?',
            'Candidate_Search' => 'Hi! I\'m Flint. I can help you search through your talent ' +
                'pool at ' + employer.Name + '. What kind of candidate are you looking for?',
            'General' => 'Hi! I\'m Flint, your AI recruiting assistant for ' + employer.Name + 
                '. How can I help you today?'
        };
        
        return greetings.containsKey(conversationType) 
            ? greetings.get(conversationType) 
            : greetings.get('General');
    }
    
    public static List<Map<String, String>> buildConversationHistory(Id interactionId) {
        List<Chat_Message__c> messages = [
            SELECT Role__c, Content__c
            FROM Chat_Message__c
            WHERE Chat_Interaction__c = :interactionId
            ORDER BY Sequence_Number__c ASC
        ];
        
        List<Map<String, String>> history = new List<Map<String, String>>();
        for (Chat_Message__c msg : messages) {
            history.add(new Map<String, String>{
                'role' => msg.Role__c.toLowerCase(),
                'content' => msg.Content__c
            });
        }
        return history;
    }
    
    public static AI_Prompt__mdt getPromptTemplate(String assistant, String convType) {
        return [
            SELECT System_Prompt__c, Temperature__c, Max_Tokens__c
            FROM AI_Prompt__mdt
            WHERE Assistant_Name__c = :assistant
            AND Conversation_Type__c = :convType
            LIMIT 1
        ];
    }
    
    public static Map<String, Object> extractJobDetails(String response, String userMsg) {
        String extractionPrompt = 'Extract job details from this conversation:\n' +
            'AI: ' + response + '\nUser: ' + userMsg + '\n\n' +
            'Return JSON with: title, department, location, employmentType, ' +
            'salaryMin, salaryMax, skills (array), experienceLevel, remoteOption, description';
        
        return ClaudeAPIService.extractStructuredData(
            response + '\n' + userMsg, 
            extractionPrompt
        );
    }
    
    public static void updateInteractionMetrics(Id interactionId, Integer tokens) {
        Chat_Interaction__c interaction = [
            SELECT Id, Total_Tokens__c, Message_Count__c
            FROM Chat_Interaction__c
            WHERE Id = :interactionId
        ];
        
        interaction.Total_Tokens__c = 
            (interaction.Total_Tokens__c ?? 0) + tokens;
        interaction.Message_Count__c = 
            (interaction.Message_Count__c ?? 0) + 2;
        interaction.Last_Message_At__c = DateTime.now();
        
        update interaction;
    }
    
    public static List<String> getSuggestedResponses(String convType, Map<String,Object> data) {
        if (convType == 'Job_Intake') {
            if (data.get('title') == null) {
                return new List<String>{
                    'Software Engineer', 'Product Manager', 'Sales Representative'
                };
            } else if (data.get('location') == null) {
                return new List<String>{
                    'Remote', 'New York, NY', 'San Francisco, CA'
                };
            }
        }
        return new List<String>();
    }
    
    public static String generateSummary(Id interactionId) {
        List<Chat_Message__c> messages = [
            SELECT Content__c FROM Chat_Message__c
            WHERE Chat_Interaction__c = :interactionId
            ORDER BY Sequence_Number__c ASC
        ];
        
        String transcript = '';
        for (Chat_Message__c msg : messages) {
            transcript += msg.Content__c + '\n';
        }
        
        Map<String, Object> summary = ClaudeAPIService.extractStructuredData(
            transcript,
            'Summarize this conversation in 2-3 sentences. Return JSON: {"summary": "..."}'
        );
        
        return (String) summary.get('summary');
    }
}