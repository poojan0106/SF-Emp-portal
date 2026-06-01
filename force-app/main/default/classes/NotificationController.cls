/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : NotificationController
 * Author          : <YourName>
 * Created Date    : Mar 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Mar 27, 2026
 * Description     : REST endpoint for candidate notifications.
 *                   Exposes GET / PATCH / DELETE via Apex REST.
 *                   All responses use typed DTO wrappers for consistency.
 *
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Mar 27, 2026  │ <YourName>   │ Initial version
 *  Mar 27, 2026  │ <YourName>   │ Added DTO wrappers for structured client responses
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
@RestResource(urlMapping='/notifications/v1/*')
global with sharing class NotificationController {

    // ─── Notification Record DTO ───────────────────────────────────────────────
    // Maps 1:1 to the Notification__c fields returned in GET.
    // Password or sensitive fields are never added here.

    global class NotificationRecord {
        public String  id;
        public String  type;
        public String  title;
        public String  description;
        public String  linkTo;
        public Boolean isRead;
        public String  priority;
        public String  createdDate;

        public NotificationRecord(Notification__c n) {
            this.id          = n.Id;
            this.type        = n.Type__c;
            this.title       = n.Title__c;
            this.description = n.Description__c;
            this.linkTo      = n.Link_To__c;
            this.isRead      = n.Is_Read__c;
            this.priority    = n.Priority__c;
            this.createdDate = n.CreatedDate != null
                                 ? String.valueOf(n.CreatedDate)
                                 : null;
        }
    }

    // ─── GET Response DTO ──────────────────────────────────────────────────────

    global class GetNotificationsResponse {
        public Boolean                  success;
        public String                   message;
        public List<NotificationRecord> notifications;
        public Integer                  unreadCount;
    }

    // ─── PATCH Response DTO ───────────────────────────────────────────────────

    global class MarkReadResponse {
        public Boolean success;
        public String  message;
        public Integer updated;     // how many records were flipped to Is_Read__c = true
    }

    // ─── DELETE Response DTO ──────────────────────────────────────────────────

    global class DeleteNotificationsResponse {
        public Boolean success;
        public String  message;
        public Integer deleted;     // how many records were removed
    }

    // ─── Error Response DTO (shared across all methods) ───────────────────────

    global class ErrorResponse {
        public Boolean success;
        public String  message;
        public String  errorDetails;

        public ErrorResponse(String message, String details) {
            this.success      = false;
            this.message      = message;
            this.errorDetails = details;
        }
    }

    // ─── GET /notifications/v1/{contactId} ────────────────────────────────────

    @HttpGet
    global static void getNotifications() {
        Id contactId = RestContext.request.requestURI.substringAfterLast('/');

        // Validate contactId present in URL
        if (String.isBlank(contactId)) {
            RestContext.response.statusCode = 400;
            RestContext.response.responseBody = Blob.valueOf(
                JSON.serialize(new ErrorResponse(
                    'Contact ID is required.',
                    'No Contact ID found in request URI.'
                ))
            );
            return;
        }

        try {
            // Fetch non-archived notifications for this contact
            List<Notification__c> rawNotifs = [
                SELECT Id, Type__c, Title__c, Description__c,
                       Link_To__c, Is_Read__c, Priority__c, CreatedDate
                FROM   Notification__c
                WHERE  Recipient__c   = :contactId
                AND    Is_Archived__c = false
                ORDER BY CreatedDate DESC
            ];

            // Map raw SObjects → clean DTOs (no SF internal fields exposed)
            List<NotificationRecord> notifDTOs = new List<NotificationRecord>();
            for (Notification__c n : rawNotifs) {
                notifDTOs.add(new NotificationRecord(n));
            }

            // Separate count query for unread — avoids iterating the full list
            Integer unreadCount = [
                SELECT COUNT()
                FROM   Notification__c
                WHERE  Recipient__c   = :contactId
                AND    Is_Read__c     = false
                AND    Is_Archived__c = false
            ];

            // Build typed response
            GetNotificationsResponse resp = new GetNotificationsResponse();
            resp.success       = true;
            resp.message       = 'Notifications retrieved successfully.';
            resp.notifications = notifDTOs;
            resp.unreadCount   = unreadCount;

            RestContext.response.statusCode   = 200;
            RestContext.response.responseBody = Blob.valueOf(JSON.serialize(resp));

        } catch (Exception e) {
            RestContext.response.statusCode   = 500;
            RestContext.response.responseBody = Blob.valueOf(
                JSON.serialize(new ErrorResponse(
                    'An unexpected error occurred.',
                    e.getMessage()
                ))
            );
        }
    }

    // ─── PATCH /notifications/v1/ ─────────────────────────────────────────────
    // Body: { "ids": ["id1","id2"], "contactId": "..." }
    //    OR { "ids": "all",         "contactId": "..." }

    @HttpPatch
    global static void markRead() {
        try {
            Map<String, Object> body = (Map<String, Object>)
                JSON.deserializeUntyped(RestContext.request.requestBody.toString());

            Object idsObj    = body.get('ids');
            String contactId = (String) body.get('contactId');

            if (String.isBlank(contactId)) {
                RestContext.response.statusCode   = 400;
                RestContext.response.responseBody = Blob.valueOf(
                    JSON.serialize(new ErrorResponse(
                        'Contact ID is required.',
                        'contactId missing from request body.'
                    ))
                );
                return;
            }

            List<Notification__c> toUpdate = new List<Notification__c>();

            // ids: 'all' → mark every unread notification for this contact
            if (idsObj instanceof String && (String) idsObj == 'all') {
                toUpdate = [
                    SELECT Id FROM Notification__c
                    WHERE  Recipient__c   = :contactId
                    AND    Is_Read__c     = false
                    AND    Is_Archived__c = false
                ];

            // ids: ['id1','id2'] → mark specific notifications only
            } else if (idsObj instanceof List<Object>) {
                List<Id> notificationIds = new List<Id>();
                for (Object id : (List<Object>) idsObj) {
                    notificationIds.add((Id) String.valueOf(id));
                }
                toUpdate = [
                    SELECT Id FROM Notification__c
                    WHERE  Id            IN :notificationIds
                    AND    Recipient__c  = :contactId    // security: own records only
                    AND    Is_Archived__c = false
                ];
            }

            for (Notification__c n : toUpdate) n.Is_Read__c = true;
            if (!toUpdate.isEmpty()) update toUpdate;

            // Build typed response
            MarkReadResponse resp = new MarkReadResponse();
            resp.success = true;
            resp.message = toUpdate.isEmpty()
                ? 'No notifications to mark as read.'
                : 'Notifications marked as read successfully.';
            resp.updated = toUpdate.size();

            RestContext.response.statusCode   = 200;
            RestContext.response.responseBody = Blob.valueOf(JSON.serialize(resp));

        } catch (Exception e) {
            RestContext.response.statusCode   = 500;
            RestContext.response.responseBody = Blob.valueOf(
                JSON.serialize(new ErrorResponse(
                    'An unexpected error occurred.',
                    e.getMessage()
                ))
            );
        }
    }

    // ─── DELETE /notifications/v1/ ────────────────────────────────────────────
    // Body: { "scope": "read", "contactId": "..." }
    //    OR { "scope": "all",  "contactId": "..." }

    @HttpDelete
    global static void deleteNotifications() {
        try {
            Map<String, Object> body = (Map<String, Object>)
                JSON.deserializeUntyped(RestContext.request.requestBody.toString());

            String scope     = (String) body.get('scope');
            String contactId = (String) body.get('contactId');

            // Validate required fields
            if (String.isBlank(contactId)) {
                RestContext.response.statusCode   = 400;
                RestContext.response.responseBody = Blob.valueOf(
                    JSON.serialize(new ErrorResponse(
                        'Contact ID is required.',
                        'contactId missing from request body.'
                    ))
                );
                return;
            }

            if (String.isBlank(scope) || (!scope.equals('all') && !scope.equals('read'))) {
                RestContext.response.statusCode   = 400;
                RestContext.response.responseBody = Blob.valueOf(
                    JSON.serialize(new ErrorResponse(
                        'Invalid scope value.',
                        'scope must be either "read" or "all". Received: ' + scope
                    ))
                );
                return;
            }

            List<Notification__c> toDelete = new List<Notification__c>();

            if (scope == 'all') {
                toDelete = [
                    SELECT Id FROM Notification__c
                    WHERE  Recipient__c   = :contactId    // scoped to this user only
                    AND    Is_Archived__c = false
                ];
            } else if (scope == 'read') {
                toDelete = [
                    SELECT Id FROM Notification__c
                    WHERE  Recipient__c   = :contactId    // scoped to this user only
                    AND    Is_Read__c     = true
                    AND    Is_Archived__c = false
                ];
            }

            if (!toDelete.isEmpty()) delete toDelete;

            // Build typed response
            DeleteNotificationsResponse resp = new DeleteNotificationsResponse();
            resp.success = true;
            resp.message = toDelete.isEmpty()
                ? 'No notifications found to delete.'
                : 'Notifications deleted successfully.';
            resp.deleted = toDelete.size();

            RestContext.response.statusCode   = 200;
            RestContext.response.responseBody = Blob.valueOf(JSON.serialize(resp));

        } catch (Exception e) {
            RestContext.response.statusCode   = 500;
            RestContext.response.responseBody = Blob.valueOf(
                JSON.serialize(new ErrorResponse(
                    'An unexpected error occurred.',
                    e.getMessage()
                ))
            );
        }
    }
}