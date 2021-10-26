import 'package:conveneapp/core/constants/exception_messages.dart';
import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:the_apple_sign_in/the_apple_sign_in.dart';

import 'package:conveneapp/apis/firebase/user.dart';
import 'package:conveneapp/core/constants/firebase_constants.dart';
import 'package:conveneapp/core/errors/errors.dart';
import 'package:conveneapp/core/type_defs/type_defs.dart';

final authApiProvider = Provider<AuthApi>((ref) => AuthApiFirebase());

abstract class AuthApi {
  Stream<User?> currentUser();

  /// - signIn with google
  FutureEitherVoid signIn();

  /// - SignIn with apple
  FutureEitherVoid signInWithApple();
  Future<void> signOut();
}

/// - Implementations for `AuthApi`
class AuthApiFirebase implements AuthApi {
  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final UserApi _userApi;
  final GoogleAuthApi _googleAuthApi;
  AuthApiFirebase(
      {FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignIn, UserApi? userApi, GoogleAuthApi? googleAuthApi})
      : _googleSignIn = googleSignIn ?? GoogleSignIn(),
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _userApi = userApi ?? UserApi(),
        _googleAuthApi = googleAuthApi ?? GoogleAuthApi();

  @override
  Stream<User?> currentUser() {
    return _firebaseAuth.authStateChanges();
  }

  @override
  FutureEitherVoid signIn() async {
    // Trigger the authentication flow
    try {
      final googleUser = await _googleAuthApi.signInWithGoogle();
      if (googleUser != null) {
        // Create a new credential
        final userCredential = await _firebaseAuth.signInWithCredential(googleUser);
        final user = userCredential.user;
        if (user != null) {
          await _userApi.addUser(uid: user.uid, email: user.email, name: user.displayName);
          return right(null);
        } else {
          throw AuthException(authExceptionMessage);
        }
      } else {
        throw AuthException('Sign in aborted by user');
      }
    } on FirebaseAuthException catch (e) {
      return left(AuthFailure(e.message ?? authExceptionMessage));
    } on BaseException catch (e) {
      return left(AuthFailure(e.message));
    } on Exception catch (_) {
      return left(AuthFailure(authExceptionMessage));
    }
  }

  @override
  Future<void> signOut() async {
    // Will signout the user's google account if logged in via google
    await _googleSignIn.signOut();

    // Once signed in, return the UserCredential
    await _firebaseAuth.signOut();
  }

  @override
  FutureEitherVoid signInWithApple() async {
    try {
      const scopes = FirebaseConstants.appleSignInScopes;
      // 1. perform the sign-in request
      final result = await TheAppleSignIn.performRequests(const [AppleIdRequest(requestedScopes: scopes)]);
      // 2. check the result
      switch (result.status) {
        case AuthorizationStatus.authorized:
          final appleIdCredential = result.credential!;
          final oAuthProvider = OAuthProvider('apple.com');
          final credential = oAuthProvider.credential(
            idToken: String.fromCharCodes(appleIdCredential.identityToken!),
            accessToken: String.fromCharCodes(appleIdCredential.authorizationCode!),
          );
          final userCredential = await _firebaseAuth.signInWithCredential(credential);
          final firebaseUser = userCredential.user!;
          if (scopes.contains(Scope.fullName)) {
            final fullName = appleIdCredential.fullName;
            if (fullName != null && fullName.givenName != null && fullName.familyName != null) {
              final displayName = '${fullName.givenName} ${fullName.familyName}';
              await firebaseUser.updateDisplayName(displayName);
            }
          }

          /// - Adds the user's document directly after the account creating
          await _userApi.addUser(uid: firebaseUser.uid, email: firebaseUser.email, name: firebaseUser.displayName);
          return right(null);
        case AuthorizationStatus.error:
          throw AuthException(result.error?.localizedFailureReason ?? authExceptionMessage);

        case AuthorizationStatus.cancelled:
          throw AuthException('Sign in aborted by user');
        default:
          throw UnimplementedError();
      }
    } on FirebaseAuthException catch (e) {
      return left(AuthFailure(e.message ?? authExceptionMessage));
    } on BaseException catch (e) {
      return left(AuthFailure(e.message));
    } on Exception catch (_) {
      return left(AuthFailure(authExceptionMessage));
    }
  }
}

/// - should only be accessed in testing
/// - this extraction is needed in order to test the functionality of the other parts
/// - below are non-mockable function
@visibleForTesting
class GoogleAuthApi {
  final GoogleSignIn _googleSignIn;
  GoogleAuthApi({
    GoogleSignIn? googleSignIn,
  }) : _googleSignIn = GoogleSignIn();
  Future<OAuthCredential?> signInWithGoogle() async {
    final result = await _googleSignIn.signIn();
    if (result == null) {
      return null;
    }
    final authentication = await result.authentication;
    return GoogleAuthProvider.credential(accessToken: authentication.accessToken, idToken: authentication.idToken);
  }
}
