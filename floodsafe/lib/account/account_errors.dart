import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

String accountErrorMessage(Object error) {
  if (error is AuthException) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'The email or password is incorrect. Try again or choose Forgot password.';
      case 'email_not_confirmed':
        return 'Confirm your email before signing in. Check your inbox and spam folder, or resend the confirmation email.';
      case 'user_already_exists':
      case 'email_exists':
        return 'If you already have an account, sign in or choose Forgot password. Creating an account again does not reset your password.';
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return 'Too many attempts. Please wait a few minutes before trying again.';
      case 'weak_password':
        return 'Choose a stronger password with at least 8 characters, including letters and numbers.';
      case 'same_password':
        return 'Choose a password different from your previous password.';
      case 'session_not_found':
      case 'session_expired':
      case 'otp_expired':
      case 'flow_state_expired':
      case 'flow_state_not_found':
        return 'This sign-in link or session has expired. Request a new email and open the latest link in this browser.';
      case 'email_provider_disabled':
      case 'signup_disabled':
        return 'Email account access is temporarily unavailable. Please try again later.';
      case 'user_banned':
        return 'This account cannot sign in. Please contact the FloodSafe administrator.';
    }
    if (error.statusCode == '429') {
      return 'Too many attempts. Please wait a few minutes before trying again.';
    }
    if (error is AuthRetryableFetchException) {
      return 'Could not reach sign-in services. Check your internet connection and try again.';
    }
    return 'Account access could not be completed. Try again, or choose Forgot password to recover access.';
  }
  if (error is TimeoutException) {
    return 'Sign-in services took too long to respond. Please try again.';
  }
  return 'Could not reach account services. Check your connection and try again.';
}
