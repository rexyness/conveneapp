import 'package:the_apple_sign_in/the_apple_sign_in.dart';

/// - this will contain all the things related to firebase, google, apple sign-in/sign-up
class FirebaseConstants {
  /// - Provides scopes that are to be request with the apple sign in
  /// - Contains `email` and `fullName`
  static const List<Scope> appleSignInScopes = [
    Scope.email,
    Scope.fullName,
  ];
}
