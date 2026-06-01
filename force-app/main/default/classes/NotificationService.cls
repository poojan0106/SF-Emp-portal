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

  public static void notify(Id recipientId, String notificationType, String title,
                            String description, String linkTo, String priority) {

    insert new Notification__c(
      Recipient__c   = recipientId,
      Type__c        = notificationType,
      Title__c       = title,
      Description__c = description,
      Link_To__c     = linkTo,
      Priority__c    = priority,
      Is_Read__c     = false
    );

    EventBus.publish(new Notification_Events__e(
      Recipient_Contact_Id__c = recipientId,
      Notification_Type__c    = notificationType,
      Title__c                = title,
      Description__c          = description,
      Link_To__c              = linkTo,
      Priority__c             = priority
    ));
  }

  public static void notifyJobMatch(Id contactId, Integer count) {
    notify(contactId,
      'Job_Match',
      count + ' new job matches found',
      'Roles matching your profile this week.',
      '/jobs',
      'High'
    );
  }

  public static void notifyInterviewInvitation(Id contactId, String company) {
    notify(contactId,
      'Interview',
      'Interview invitation from ' + company,
      'You have been invited to interview. Review and confirm.',
      '/interviews',
      'Urgent'
    );
  }

  public static void notifyApplicationUpdate(Id contactId, String role, String status) {
    notify(contactId,
      'Application',
      'Application Update: ' + role,
      'Your application status changed to: ' + status + '.',
      '/applications',
      'Normal'
    );
  }

  public static void notifyProfileReminder(Id contactId, Integer pct) {
    if (pct >= 70) return;
    notify(contactId,
      'Profile_Reminder',
      'Your profile is ' + pct + '% complete',
      'Complete your profile so employers can find you.',
      '/profile',
      'Low'
    );
  }

}