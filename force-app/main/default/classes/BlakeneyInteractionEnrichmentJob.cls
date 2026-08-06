public with sharing class BlakeneyInteractionEnrichmentJob implements Queueable, Database.AllowsCallouts {
    private Id contactId;
    private Id careerIntentId;
    private Id careerConstraintsId;
    private String interactionType;
    private String updatedFields;
    private String sessionId;

    public BlakeneyInteractionEnrichmentJob(String contactId, String interactionType, String updatedFields, String careerIntentId, String careerConstraintsId, String sessionId) {
        this.contactId = parseId(contactId);
        this.careerIntentId = parseId(careerIntentId);
        this.careerConstraintsId = parseId(careerConstraintsId);
        this.interactionType = interactionType;
        this.updatedFields = updatedFields;
        this.sessionId = sessionId;
    }

    public void execute(QueueableContext context) {
        if (contactId == null) return;
        AICVEnhancementService.enhanceContactWithBlakeneyContext(
            contactId,
            careerIntentId,
            careerConstraintsId,
            interactionType,
            updatedFields,
            sessionId
        );
    }

    private static Id parseId(String value) {
        if (String.isBlank(value)) return null;
        try {
            return (Id) value;
        } catch (Exception e) {
            return null;
        }
    }
}