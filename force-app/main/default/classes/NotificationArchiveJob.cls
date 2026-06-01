/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : NotificationArchiveJob
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

global class NotificationArchiveJob implements Schedulable {

  global void execute(SchedulableContext sc) {

    DateTime cutoff = DateTime.now().addDays(-30);

    List<Notification__c> old = [
      SELECT Id FROM Notification__c
      WHERE  Is_Read__c     = true
      AND    CreatedDate    < :cutoff
      AND    Is_Archived__c = false
    ];

    for (Notification__c n : old) {
      n.Is_Archived__c    = true;
      n.Archived_Date__c  = DateTime.now();
    }

    update old;
  }
}

// To schedule — run this once in Anonymous Apex:
// System.schedule('Notif Archive', '0 0 2 * * ?', new NotificationArchiveJob());