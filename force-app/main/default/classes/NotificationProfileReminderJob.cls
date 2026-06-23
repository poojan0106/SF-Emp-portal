global class NotificationProfileReminderJob implements Schedulable {
  global void execute(SchedulableContext sc) {
    NotificationService.notifyProfileReminderForStaleProfiles();
  }
}