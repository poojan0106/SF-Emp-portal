@IsTest
public class ZipcodeBaseCalloutTest {
    @IsTest
    static void testGetZipcodeDetails() {
        // Create a mock HTTP response
        ZipcodeBaseCalloutMock mock = new ZipcodeBaseCalloutMock();
        Test.setMock(HttpCalloutMock.class, mock);
        
        // Prepare test data for the request
        ZipcodeBaseCallout.RequestWrapper request = new ZipcodeBaseCallout.RequestWrapper();
        request.zipCode = '12345';
        
        List<ZipcodeBaseCallout.RequestWrapper> requestList = new List<ZipcodeBaseCallout.RequestWrapper> { request };
        
        // Execute the method
        List<ZipcodeBaseCallout.ResponseWrapper> responses = ZipcodeBaseCallout.getZipcodeDetails(requestList);
        
        // Verify results
        System.assertEquals(1, responses.size(), 'Expected one response');
        System.assertEquals('12345', responses[0].zipCode, 'Zipcode should match request');
        System.assertEquals('Sample City', responses[0].city, 'City should match mock response');
        System.assertEquals('Sample Country', responses[0].country, 'Country should match mock response');
    }
    
    // Mock HTTP response class
    private class ZipcodeBaseCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"city": "Sample City", "country": "Sample Country"}');
            return res;
        }
    }
}