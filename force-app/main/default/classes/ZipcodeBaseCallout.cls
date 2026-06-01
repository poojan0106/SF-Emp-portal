public class ZipcodeBaseCallout {
    @InvocableMethod(label='Fetch Zipcode Details' description='Fetches details based on a zipcode using the Zipcodebase API')
    public static List<ResponseWrapper> getZipcodeDetails(List<RequestWrapper> requestList) {
        List<ResponseWrapper> responses = new List<ResponseWrapper>();
        for (RequestWrapper req : requestList) {
            try {
                Http http = new Http();
                HttpRequest request = new HttpRequest();
                request.setEndpoint('callout:Zipcodebase_API/your_endpoint'); // Update to your named credential and endpoint
                request.setMethod('GET');
                request.setHeader('apikey', 'your_api_key'); // Add API key if required
                request.setHeader('Content-Type', 'application/json');
                
                HttpResponse response = http.send(request);
                
                if (response.getStatusCode() == 200) {
                    // Parse JSON response and store relevant data in ResponseWrapper
                    Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                    ResponseWrapper wrapper = new ResponseWrapper();
                    wrapper.zipCode = req.zipCode;
                    wrapper.city = (String) responseData.get('city'); // Update based on actual response structure
                    wrapper.country = (String) responseData.get('country'); // Update based on actual response structure
                    responses.add(wrapper);
                } else {
                    throw new CalloutException('Failed callout: ' + response.getStatus());
                }
            } catch (Exception e) {
                System.debug('Error: ' + e.getMessage());
            }
        }
        return responses;
    }
    
    public class RequestWrapper {
        @InvocableVariable(required=true)
        public String zipCode;
    }

    public class ResponseWrapper {
        @InvocableVariable
        public String zipCode;
        @InvocableVariable
        public String city;
        @InvocableVariable
        public String country;
    }
}