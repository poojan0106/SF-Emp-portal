/**
 * Salesforce REST API Controller for Subscription Queries
 * Handles querying subscription data by account ID
 *
 * Route:
 * POST /subscription/query - Query subscription by accountId
 */

@RestResource(urlMapping='/subscription/query')
global class SubscriptionQueryController {

  /**
   * POST /subscription/query
   * Query subscription record for an account
   */
  @HttpPost
  global static void handlePost() {
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

      // Query for subscription record
      List<Employer_Subscription__c> subscriptions = [
        SELECT
          Id,
          Account__c,
          Status__c,
          Stripe_Subscription_ID__c,
          Stripe_Customer_ID__c,
          Subscription_Name__c,
          Subscription_Start_Date__c,
          Subscription_End_Date__c,
          Updated_At__c
        FROM Employer_Subscription__c
        WHERE Account__c = :accountId
        ORDER BY Updated_At__c DESC, CreatedDate DESC
        LIMIT 1
      ];

      if (subscriptions.isEmpty()) {
        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
          'success' => true,
          'subscription' => null,
          'message' => 'No subscription found'
        }));
        return;
      }

      Employer_Subscription__c sub = subscriptions[0];

      res.statusCode = 200;
      res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
        'success' => true,
        'subscription' => new Map<String, Object>{
          'Id' => sub.Id,
          'Account__c' => sub.Account__c,
          'Status__c' => sub.Status__c,
          'Stripe_Subscription_ID__c' => sub.Stripe_Subscription_ID__c,
          'Stripe_Customer_ID__c' => sub.Stripe_Customer_ID__c,
          'Subscription_Name__c' => sub.Subscription_Name__c,
          'Subscription_Start_Date__c' => sub.Subscription_Start_Date__c,
          'Subscription_End_Date__c' => sub.Subscription_End_Date__c,
          'Updated_At__c' => sub.Updated_At__c
        }
      }));

    } catch (Exception e) {
      System.debug('❌ Error querying subscription: ' + e.getMessage());
      System.debug('Stack trace: ' + e.getStackTraceString());
      sendError(500, 'Error querying subscription: ' + e.getMessage());
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
    System.debug('❌ Error response: ' + statusCode + ' - ' + message);
  }
}