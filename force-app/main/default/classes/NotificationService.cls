/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : NotificationService
 * Author          : <YourName>
 * Created Date    : Mar 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Mar 27, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Mar 27, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public with sharing class NotificationService {

  public class NotificationRequest {
    public Id recipientId;
    public String notificationType;
    public String title;
    public String description;
    public String linkTo;
    public String priority;
  }

  public static void notifyMany(List<NotificationRequest> requests) {
    if (requests == null || requests.isEmpty()) return;

    List<Notification__c> notifications = new List<Notification__c>();
    List<Notification_Events__e> events = new List<Notification_Events__e>();

    for (NotificationRequest request : requests) {
      if (request == null || request.recipientId == null || String.isBlank(request.notificationType)) {
        continue;
      }

      String priority = String.isBlank(request.priority) ? 'Normal' : request.priority;
      String title = truncate(request.title, 100);
      String description = truncate(request.description, 500);

      notifications.add(new Notification__c(
        Recipient__c = request.recipientId,
        Type__c = request.notificationType,
        Title__c = title,
        Description__c = description,
        Link_To__c = request.linkTo,
        Priority__c = priority,
        Is_Read__c = false,
        Is_Archived__c = false
      ));

      events.add(new Notification_Events__e(
        Recipient_Contact_Id__c = request.recipientId,
        Notification_Type__c = request.notificationType,
        Title__c = title,
        Description__c = description,
        Link_To__c = request.linkTo,
        Priority__c = priority
      ));
    }

    if (!notifications.isEmpty()) insert notifications;
    if (!events.isEmpty()) EventBus.publish(events);
  }

  public static void notify(Id recipientId, String notificationType, String title,
                            String description, String linkTo, String priority) {

    NotificationRequest request = new NotificationRequest();
    request.recipientId = recipientId;
    request.notificationType = notificationType;
    request.title = title;
    request.description = description;
    request.linkTo = linkTo;
    request.priority = priority;

    notifyMany(new List<NotificationRequest>{ request });
  }

  public static void notifyJobMatch(Id contactId, Integer count) {
    notify(contactId,
      'Job_Match',
      count + ' new job matches found',
      'Roles matching your profile this week.',
      '/discover-employers',
      'High'
    );
  }

  public static void notifyInterviewInvitation(Id contactId, String company) {
    notify(contactId,
      'Interview',
      'Interview invitation from ' + company,
      'You have been invited to interview. Review and confirm.',
      '/dashboard',
      'Urgent'
    );
  }

  public static void notifyInterviewInvitation(Id contactId, String company, String roleTitle) {
    String description = 'You have been invited to interview';
    if (String.isNotBlank(roleTitle)) {
      description += ' for ' + roleTitle;
    }
    description += '. Review and confirm.';

    notify(contactId,
      'Interview',
      'Interview invitation from ' + company,
      description,
      '/dashboard',
      'Urgent'
    );
  }

  public static void notifyApplicationUpdate(Id contactId, String role, String status) {
    notify(contactId,
      'Application',
      'Application Update: ' + role,
      'Your application status changed to: ' + status + '.',
      '/dashboard',
      'Normal'
    );
  }

  public static void notifyCompanyHiring(Id contactId, String company, String roleTitle) {
    String description = (String.isBlank(company) ? 'A company you liked' : company) + ' posted ';
    description += String.isBlank(roleTitle) ? 'a new role' : roleTitle;
    description += ' that may fit your profile.';

    notify(contactId,
      'Company_Hiring',
      'Company you swiped is now hiring',
      description,
      '/discover-employers',
      'Normal'
    );
  }

  public static void notifyBlakeneyMessage(Id contactId, String message) {
    notify(contactId,
      'Message',
      'Message from Blakeney',
      String.isBlank(message) ? 'Blakeney has a new career update for you.' : message,
      '/dashboard',
      'Normal'
    );
  }

  public static void notifyProfileReminder(Id contactId, Integer pct) {
    if (pct >= 70) return;
    notify(contactId,
      'Profile_Reminder',
      'Your profile is ' + pct + '% complete',
      'Complete your profile so employers can find you.',
      '/onboarding',
      'Low'
    );
  }

  public static void notifyProfileReminderForStaleProfiles() {
    Date cutoff = Date.today().addDays(-7);
    List<Contact> contacts = [
      SELECT Id, Profile_Completeness__c, CreatedDate
      FROM Contact
      WHERE Profile_Completeness__c < 70
      AND CreatedDate <= :cutoff
      AND Id NOT IN (
        SELECT Recipient__c
        FROM Notification__c
        WHERE Type__c = 'Profile_Reminder'
        AND CreatedDate = LAST_N_DAYS:7
      )
      LIMIT 2000
    ];

    List<NotificationRequest> requests = new List<NotificationRequest>();
    for (Contact contact : contacts) {
      Integer pct = contact.Profile_Completeness__c == null ? 0 : contact.Profile_Completeness__c.intValue();
      NotificationRequest request = new NotificationRequest();
      request.recipientId = contact.Id;
      request.notificationType = 'Profile_Reminder';
      request.title = 'Your profile is ' + pct + '% complete';
      request.description = 'Complete your profile so employers can find you.';
      request.linkTo = '/onboarding';
      request.priority = 'Low';
      requests.add(request);
    }

    notifyMany(requests);
  }

  private static String truncate(String value, Integer maxLength) {
    if (value == null) return null;
    return value.length() > maxLength ? value.substring(0, maxLength) : value;
  }

}
