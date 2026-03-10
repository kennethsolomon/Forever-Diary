import Foundation

enum AWSConfig {
    static let region = "ap-southeast-2"          // Cognito Identity Pool + User Pool region
    static let apiGatewayRegion = "ap-southeast-1" // Lambda / API Gateway region
    static let cognitoIdentityPoolId = "ap-southeast-2:077a9a40-8cf3-4f46-8632-34acb4843168"
    static let apiGatewayURL = "https://dnfa0j98qk.execute-api.ap-southeast-1.amazonaws.com/prod"
    static let s3Bucket = "forever-diary-photos-800759"

    // Cognito User Pool
    static let cognitoUserPoolId = "ap-southeast-2_y15oFoXar"
    static let cognitoUserPoolClientId = "br9m1dgkps1hhb25omkoelehn"

    // Google Sign-In — create OAuth 2.0 Client ID (iOS) in Google Cloud Console
    static let googleClientId = "189908989468-l54fh8m4tmv5shibmo2om1mi8ta917hb.apps.googleusercontent.com"
    static let googleReversedClientId = "com.googleusercontent.apps.189908989468-l54fh8m4tmv5shibmo2om1mi8ta917hb"
}
