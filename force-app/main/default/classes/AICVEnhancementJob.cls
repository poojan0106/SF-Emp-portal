public class AICVEnhancementJob implements Queueable, Database.AllowsCallouts {
    private final Id contactId;

    public AICVEnhancementJob(Id contactId) {
        this.contactId = contactId;
    }

    public void execute(QueueableContext context) {
        AICVEnhancementService.enhanceContact(contactId);
    }
}
