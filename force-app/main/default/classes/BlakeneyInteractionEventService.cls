public with sharing class BlakeneyInteractionEventService {
    public static void publish(Id contactId, String interactionType, String updatedFields, Id careerIntentId, Id careerConstraintsId, String sessionId) {
        if (contactId == null || !Schema.getGlobalDescribe().containsKey('Blakeney_Interaction_Complete__e')) return;

        try {
            Blakeney_Interaction_Complete__e eventRow = new Blakeney_Interaction_Complete__e(
                Contact_Id__c = String.valueOf(contactId),
                Interaction_Type__c = String.isBlank(interactionType) ? 'Profile Update' : interactionType,
                Updated_Fields__c = safe(updatedFields),
                Career_Intent_Id__c = careerIntentId == null ? null : String.valueOf(careerIntentId),
                Career_Constraints_Id__c = careerConstraintsId == null ? null : String.valueOf(careerConstraintsId),
                Session_Id__c = sessionId
            );
            EventBus.publish(eventRow);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Blakeney interaction event skipped: ' + e.getMessage());
        }
    }

    private static String safe(String value) {
        if (String.isBlank(value)) return value;
        return value.length() > 32768 ? value.substring(0, 32768) : value;
    }
}