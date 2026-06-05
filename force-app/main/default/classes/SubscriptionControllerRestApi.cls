/**                                                                                                                                       
   * Salesforce REST API Controller for Subscription Management                                                                             
   * Handles creating, updating, cancelling, and retrieving subscriptions                                                                   
   * Integrated with Stripe for billing
   */

  @RestResource(urlMapping='/stripe-Subscription/*')
  global class SubscriptionControllerRestApi {

    /**
     * Helper to extract the endpoint path from the request URI
     */
    private static String getEndpointPath() {
      RestRequest req = RestContext.request;
      String path = req.requestURI;
      System.debug('Full URI: ' + path);

      // Extract path after /stripe-Subscription/
      Integer idx = path.indexOf('/stripe-Subscription/');
      if (idx >= 0) {
        String endpoint = path.substring(idx + '/stripe-Subscription/'.length());
        System.debug('Extracted endpoint: ' + endpoint);
        return endpoint;
      }
      return '';
    }

    /**
     * Helper to convert ISO datetime string to Date
     */
    private static Date parseIsoDatetime(String isoDatetime) {
      if (String.isBlank(isoDatetime)) {
        return null;
      }
      try {
        // Parse ISO datetime to DateTime, then extract date
        DateTime dt = DateTime.valueOf(isoDatetime.replace('T', ' ').replace('Z', ''));
        return dt.date();
      } catch (Exception e) {
        // If parsing fails, try just the date part
        try {
          String dateString = isoDatetime.split('T')[0];
          return Date.valueOf(dateString);
        } catch (Exception e2) {
          System.debug('Error parsing date: ' + isoDatetime + ' - ' + e2.getMessage());
          return null;
        }
      }
    }

    @HttpGet
    global static void handleGet() {
      String endpoint = getEndpointPath();
      System.debug('GET endpoint: ' + endpoint);

      if (endpoint.equals('get')) {
        getSubscription();
      } else {
        sendError(400, 'Unknown GET endpoint: ' + endpoint);
      }
    }

    @HttpPost
    global static void handlePost() {
      String endpoint = getEndpointPath();
      System.debug('POST endpoint: ' + endpoint);

      if (endpoint.equals('create')) {
        createSubscription();
      } else {
        sendError(400, 'Unknown POST endpoint: ' + endpoint);
      }
    }

    @HttpPatch
    global static void handlePatch() {
      String endpoint = getEndpointPath();
      System.debug('PATCH endpoint: ' + endpoint);

      if (endpoint.equals('update')) {
        updateSubscription();
      } else if (endpoint.equals('lock-access')) {
        lockProfileAccess();
      } else if (endpoint.equals('unlock-access')) {
        unlockProfileAccess();
      } else {
        sendError(400, 'Unknown PATCH endpoint: ' + endpoint);
      }
    }

    @HttpDelete
    global static void handleDelete() {
      String endpoint = getEndpointPath();
      System.debug('DELETE endpoint: ' + endpoint);

      if (endpoint.equals('cancel')) {
        cancelSubscription();
      } else {
        sendError(400, 'Unknown DELETE endpoint: ' + endpoint);
      }
    }

    /**
     * GET /stripe-Subscription/get
     * Get subscription details by accountId
     */
    private static void getSubscription() {
      try {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        Map<String, Object> params = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
        String accountId = (String) params.get('accountId');
        System.debug('GET subscription for accountId: ' + accountId);

        if (String.isBlank(accountId)) {
          res.statusCode = 400;
          res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => 'Missing required parameter: accountId'
          }));
          return;
        }

        // Find subscription for this account
        List<Employer_Subscription__c> subscriptions = [
          SELECT
            Id,
            Stripe_Customer_ID__c,
            Stripe_Subscription_ID__c,
            Status__c,
            Subscription_Name__c,
            Subscription_Start_Date__c,
            Subscription_End_Date__c
          FROM Employer_Subscription__c
          WHERE Account__c = :accountId
          ORDER BY CreatedDate DESC
		  LIMIT 1
        ];

        if (subscriptions.isEmpty()) {
          res.statusCode = 200;
          res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => true,
            'message' => 'No subscription found'
          }));
          return;
        }

        Employer_Subscription__c sub = subscriptions[0];

        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
          'success' => true,
          'id' => sub.Id,
          'stripeCustomerId' => sub.Stripe_Customer_ID__c,
          'stripeSubscriptionId' => sub.Stripe_Subscription_ID__c,
          'status' => sub.Status__c,
          'productName' => sub.Subscription_Name__c,
          'startDate' => sub.Subscription_Start_Date__c,
          'endDate' => sub.Subscription_End_Date__c
        }));
      } catch (Exception e) {
        System.debug('Error in getSubscription: ' + e.getMessage() + ' ' + e.getStackTraceString());
        sendError(500, 'Error retrieving subscription: ' + e.getMessage());
      }
    }

    /**
     * POST /stripe-Subscription/create
     * Create a new subscription record linked to an account
     */
    private static void createSubscription() {
      try {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        Map<String, Object> params = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
        System.debug('Create subscription params: ' + params);

        String accountId = (String) params.get('accountId');
        String plan = (String) params.get('plan');
        String stripeSubscriptionId = (String) params.get('stripeSubscriptionId');
        String stripeCustomerId = (String) params.get('stripeCustomerId');
        String currentPeriodStart = (String) params.get('currentPeriodStart');
        String currentPeriodEnd = (String) params.get('currentPeriodEnd');
        String productName = (String) params.get('productName');

        // Validate required fields
        if (String.isBlank(accountId)) {
          res.statusCode = 400;
          res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => 'Missing required field: accountId'
          }));
          return;
        }

        // Update Account with Stripe Customer ID and enable profile access
        Account acc = new Account(
          Id = accountId,
          Stripe_Customer_ID__c = stripeCustomerId,
          Profile_Access_Enabled__c = true
        );
        update acc;
        System.debug('Account updated: ' + accountId);
        unlockTalentPoolProfiles(accountId);

        // Parse dates safely
        Date startDate = parseIsoDatetime(currentPeriodStart);
        Date endDate = parseIsoDatetime(currentPeriodEnd);
        System.debug('Parsed dates - Start: ' + startDate + ', End: ' + endDate);

        List<Employer_Subscription__c> existingSubscriptions = [
          SELECT Id
          FROM Employer_Subscription__c
          WHERE Stripe_Subscription_ID__c = :stripeSubscriptionId
             OR Account__c = :accountId
          ORDER BY CreatedDate DESC
          LIMIT 1
        ];

        Employer_Subscription__c subscription;
        if (existingSubscriptions.isEmpty()) {
          subscription = new Employer_Subscription__c(Account__c = accountId);
        } else {
          subscription = existingSubscriptions[0];
        }

        subscription.Status__c = 'Active';
        subscription.Stripe_Subscription_ID__c = stripeSubscriptionId;
        subscription.Stripe_Customer_ID__c = stripeCustomerId;
        subscription.Subscription_Start_Date__c = startDate;
        subscription.Subscription_End_Date__c = endDate != null ? endDate : Date.Today().addDays(28);
        subscription.Subscription_Name__c = String.isNotBlank(productName) ? productName : plan;
        subscription.Subscription_Tier__c = 'Professional';
        subscription.Updated_At__c = DateTime.now();

        upsert subscription;
        System.debug('Subscription upserted: ' + subscription.Id);

        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
          'success' => true,
          'subscriptionId' => subscription.Id,
          'message' => 'Subscription created successfully'
        }));
      } catch (Exception e) {
        System.debug('Error in createSubscription: ' + e.getMessage() + ' ' + e.getStackTraceString());
        sendError(500, 'Error creating subscription: ' + e.getMessage());
      }
    }

    /**
     * PATCH /stripe-Subscription/update
     * Update an existing subscription record
     */
    private static void updateSubscription() {
      try {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        Map<String, Object> params = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());

        String accountId = (String) params.get('accountId');
        String status = (String) params.get('status');
        String currentPeriodEnd = (String) params.get('currentPeriodEnd');

        if (String.isBlank(accountId)) {
          res.statusCode = 400;
          res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => 'Missing required field: accountId'
          }));
          return;
        }

        // Find subscription for this account
        List<Employer_Subscription__c> subscriptions = [
          SELECT Id FROM Employer_Subscription__c
          WHERE Account__c = :accountId
          LIMIT 1
        ];

        if (subscriptions.isEmpty()) {
          res.statusCode = 404;
          res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => 'Subscription not found for account'
          }));
          return;
        }

        Employer_Subscription__c sub = subscriptions[0];

        if (String.isNotBlank(status)) {
          sub.Status__c = status;
        }
        if (String.isNotBlank(currentPeriodEnd)) {
          sub.Subscription_End_Date__c = parseIsoDatetime(currentPeriodEnd);
        }

        sub.Updated_At__c = DateTime.now();
        update sub;

        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
          'success' => true,
          'subscriptionId' => sub.Id,
          'message' => 'Subscription updated successfully'
        }));
      } catch (Exception e) {
        sendError(500, 'Error updating subscription: ' + e.getMessage());
      }
    }

    /**
     * DELETE /stripe-Subscription/cancel
     * Cancel subscription and lock profile access
     */
    private static void cancelSubscription() {
      try {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        Map<String, Object> params = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());

        String accountId = (String) params.get('accountId');

        if (String.isBlank(accountId)) {
          res.statusCode = 400;
          res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => 'Missing required field: accountId'
          }));
          return;
        }

        // Find subscription for this account
        List<Employer_Subscription__c> subscriptions = [
          SELECT Id FROM Employer_Subscription__c
          WHERE Account__c = :accountId
          LIMIT 1
        ];

        if (!subscriptions.isEmpty()) {
          Employer_Subscription__c sub = subscriptions[0];
          sub.Status__c = 'Cancelled';
          sub.Updated_At__c = DateTime.now();
          update sub;
        }

        // Lock profile access on account
        Account acc = new Account(
          Id = accountId,
          Profile_Access_Enabled__c = false
        );
        update acc;

        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
          'success' => true,
          'message' => 'Subscription cancelled and profile access locked'
        }));
      } catch (Exception e) {
        sendError(500, 'Error cancelling subscription: ' + e.getMessage());
      }
    }

    /**
     * PATCH /stripe-Subscription/lock-access
     * Lock profile access on account
     */
    private static void lockProfileAccess() {
      try {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        Map<String, Object> params = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());

        String accountId = (String) params.get('accountId');

        if (String.isBlank(accountId)) {
          res.statusCode = 400;
          res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => 'Missing required field: accountId'
          }));
          return;
        }

        Account acc = new Account(
          Id = accountId,
          Profile_Access_Enabled__c = false
        );
        update acc;
        System.debug('Profile access locked for: ' + accountId);

        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
          'success' => true,
          'message' => 'Profile access locked successfully'
        }));
      } catch (Exception e) {
        System.debug('Error in lockProfileAccess: ' + e.getMessage() + ' ' + e.getStackTraceString());
        sendError(500, 'Error locking profile access: ' + e.getMessage());
      }
    }

    /**
     * PATCH /stripe-Subscription/unlock-access
     * Unlock profile access on account
     */
    private static void unlockProfileAccess() {
      try {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        Map<String, Object> params = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());

        String accountId = (String) params.get('accountId');

        if (String.isBlank(accountId)) {
          res.statusCode = 400;
          res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => 'Missing required field: accountId'
          }));
          return;
        }

        Account acc = new Account(
          Id = accountId,
          Profile_Access_Enabled__c = true
        );
        update acc;
        unlockTalentPoolProfiles(accountId);
        System.debug('Profile access unlocked for: ' + accountId);

        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
          'success' => true,
          'message' => 'Profile access unlocked successfully'
        }));
      } catch (Exception e) {
        System.debug('Error in unlockProfileAccess: ' + e.getMessage() + ' ' + e.getStackTraceString());
        sendError(500, 'Error unlocking profile access: ' + e.getMessage());
      }
    }

    /**
     * Helper to send error response
     */
    private static void sendError(Integer statusCode, String message) {
      RestContext.response.statusCode = statusCode;
      RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
        'success' => false,
        'message' => message
      }));
    }

    private static void unlockTalentPoolProfiles(String accountId) {
      List<CampaignMember> membersToUnlock = [
        SELECT Id, Full_Profile_Unlocked__c, Unlocked_Date__c
        FROM CampaignMember
        WHERE Campaign.Employer__c = :accountId
        AND Full_Profile_Unlocked__c = false
        LIMIT 10000
      ];

      for (CampaignMember member : membersToUnlock) {
        member.Full_Profile_Unlocked__c = true;
        member.Unlocked_Date__c = DateTime.now();
      }

      if (!membersToUnlock.isEmpty()) {
        update membersToUnlock;
        System.debug('Unlocked talent pool profiles: ' + membersToUnlock.size());
      }
    }
  }
