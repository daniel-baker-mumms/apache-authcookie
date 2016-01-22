package Apache2_4::AuthCookie;

# ABSTRACT: Perl Authentication and Authorization via cookies for Apache 2.4

use strict;
use base 'Apache2::AuthCookie::Base';
use Apache::AuthCookie::Autobox;
use Apache2::Log;
use Apache2::Const -compile => qw(AUTHZ_GRANTED AUTHZ_DENIED AUTHZ_DENIED_NO_USER);

# You really do not need this provider at all.  This provides an implementation
# for "Require user ..." directives, that is compatible with mod_authz_core
# (with the exception that expressions are not supported).  You should really
# just let mod_authz_core be your "user" authz provider.  Nevertheless, due to
# the fact that AuthCookie was released for Apache 2.4 with documentation that
# shows this is needed, we leave this implementation for backwards
# compatibility.
sub authz_handler  {
    my ($auth_type, $r, $requires) = @_;

    my $user = $r->user;

    if ($user->is_blank) {
        # user is not yet authenticated
        return Apache2::Const::AUTHZ_DENIED_NO_USER;
    }

    if ($requires->is_blank) {
        $r->server->log_error(q[Your 'Require user ...' config does not specify any users]);
        return Apache2::Const::AUTHZ_DENIED;
    }

    my $debug = $r->dir_config("AuthCookieDebug") || 0;

    $r->server->log_error("authz user=$user type=$auth_type req=$requires") if $debug >=3;

    for my $valid_user (split /\s+/, $requires) {
        if ($user eq $valid_user) {
            return Apache2::Const::AUTHZ_GRANTED;
        }
    }

    # log a message similar to mod_authz_user
    $r->log->debug(sprintf
        q[access to %s failed, reason: user '%s' does not meet 'require'ments for a ].
        q[user to be allowed access], $r->uri, $r->user);

    return Apache2::Const::AUTHZ_DENIED;
}

1;

__END__

=head1 SYNOPSIS

Make sure your mod_perl is at least 2.0.9, with StackedHandlers,
MethodHandlers, Authen, and Authz compiled in.

 # In httpd.conf or .htaccess:
 PerlModule Sample::Apache2::AuthCookieHandler
 PerlSetVar WhatEverPath /
 PerlSetVar WhatEverLoginScript /login.pl

 # The following line is optional - it allows you to set the domain
 # scope of your cookie.  Default is the current domain.
 PerlSetVar WhatEverDomain .yourdomain.com

 # Use this to only send over a secure connection
 PerlSetVar WhatEverSecure 1

 # Use this if you want user session cookies to expire if the user
 # doesn't request a auth-required or recognize_user page for some
 # time period.  If set, a new cookie (with updated expire time)
 # is set on every request.
 PerlSetVar WhatEverSessionTimeout +30m

 # to enable the HttpOnly cookie property, use HttpOnly.
 # this is an MS extension.  See:
 # http://msdn.microsoft.com/workshop/author/dhtml/httponly_cookies.asp
 PerlSetVar WhatEverHttpOnly 1

 # Usually documents are uncached - turn off here
 PerlSetVar WhatEverCache 1

 # Use this to make your cookies persistent (+2 hours here)
 PerlSetVar WhatEverExpires +2h

 # Use to make AuthCookie send a P3P header with the cookie
 # see http://www.w3.org/P3P/ for details about what the value 
 # of this should be
 PerlSetVar WhatEverP3P "CP=\"...\""

 # These documents require user to be logged in.
 <Location /protected>
  AuthType Sample::Apache2::AuthCookieHandler
  AuthName WhatEver
  PerlAuthenHandler Sample::Apache2::AuthCookieHandler->authenticate
  Require valid-user
 </Location>

 # How to handle a custom requirement (non-user).
 PerlAddAuthzProvider species Sample::Apache2::AuthCookieHandler->authz_species
 <Location /protected/species>
   Require species klingon
 </Location>

 # These documents don't require logging in, but allow it.
 <FilesMatch "\.ok$">
  AuthType Sample::Apache2::AuthCookieHandler
  AuthName WhatEver
  PerlFixupHandler Sample::Apache2::AuthCookieHandler->recognize_user
 </FilesMatch>

 # This is the action of the login.pl script above.
 <Files LOGIN>
  AuthType Sample::Apache2::AuthCookieHandler
  AuthName WhatEver
  SetHandler perl-script
  PerlResponseHandler Sample::Apache2::AuthCookieHandler->login
 </Files>

=head1 DESCRIPTION

This module is for C<mod_perl> version 2 for C<Apache> version 2.4.x.  If you
are running mod_perl version 1, you need B<Apache::AuthCookie> instead.  If you
are running C<Apache> 2.0.0-2.2.x, you need B<Apache2::AuthCookie> instead.

B<Apache2_4::AuthCookie> allows you to intercept a user's first unauthenticated
access to a protected document. The user will be presented with a custom form
where they can enter authentication credentials. The credentials are posted to
the server where AuthCookie verifies them and returns a session key.

The session key is returned to the user's browser as a cookie. As a cookie, the
browser will pass the session key on every subsequent accesses. AuthCookie will
verify the session key and re-authenticate the user.

All you have to do is write a custom module that inherits from AuthCookie.
Your module is a class which implements two methods:

=over 4

=item C<authen_cred()>

Verify the user-supplied credentials and return a session key.  The session key
can be any string - often you'll use some string containing username, timeout
info, and any other information you need to determine access to documents, and
append a one-way hash of those values together with some secret key.

=item C<authen_ses_key()>

Verify the session key (previously generated by C<authen_cred()>, possibly
during a previous request) and return the user ID.  This user ID will be fed to
C<$r-E<gt>user()> to set Apache's idea of who's logged in.

=back

By using AuthCookie versus Apache's built-in AuthBasic you can design your own
authentication system.  There are several benefits.

=over 4

=item 1.

The client doesn't *have* to pass the user credentials on every subsequent
access.  If you're using passwords, this means that the password can be sent on
the first request only, and subsequent requests don't need to send this
(potentially sensitive) information.  This is known as "ticket-based"
authentication.

=item 2.

When you determine that the client should stop using the credentials/session
key, the server can tell the client to delete the cookie.  Letting users "log
out" is a notoriously impossible-to-solve problem of AuthBasic.

=item 3.

AuthBasic dialog boxes are ugly.  You can design your own HTML login forms when
you use AuthCookie.

=item 4.

You can specify the domain of a cookie using C<PerlSetVar> commands.  For
instance, if your AuthName is C<WhatEver>, you can put the command 

 PerlSetVar WhatEverDomain .yourhost.com

into your server setup file and your access cookies will span all hosts ending
in C<.yourhost.com>.

=item 5.

You can optionally specify the name of your cookie using the C<CookieName>
directive.  For instance, if your AuthName is C<WhatEver>, you can put the
command

 PerlSetVar WhatEverCookieName MyCustomName

into your server setup file and your cookies for this AuthCookie realm will be
named MyCustomName.  Default is AuthType_AuthName.

=back

This is the flow of the authentication handler, less the details of the
redirects. Two HTTP_MOVED_TEMPORARILY's are used to keep the client from
displaying the user's credentials in the Location field. They don't really
change AuthCookie's model, but they do add another round-trip request to the
client.

=for html
<PRE>

 (-----------------------)     +---------------------------------+
 ( Request a protected   )     | AuthCookie sets custom error    |
 ( page, but user hasn't )---->| document and returns            |
 ( authenticated (no     )     | HTTP_FORBIDDEN. Apache abandons |      
 ( session key cookie)   )     | current request and creates sub |      
 (-----------------------)     | request for the error document. |<-+
                               | Error document is a script that |  |
                               | generates a form where the user |  |
                 return        | enters authentication           |  |
          ^------------------->| credentials (login & password). |  |
         / \      False        +---------------------------------+  |
        /   \                                   |                   |
       /     \                                  |                   |
      /       \                                 V                   |
     /         \               +---------------------------------+  |
    /   Pass    \              | User's client submits this form |  |
   /   user's    \             | to the LOGIN URL, which calls   |  |
   | credentials |<------------| AuthCookie->login().            |  |
   \     to      /             +---------------------------------+  |
    \authen_cred/                                                   |
     \ function/                                                    |
      \       /                                                     |
       \     /                                                      |
        \   /            +------------------------------------+     |
         \ /   return    | Authen cred returns a session      |  +--+
          V------------->| key which is opaque to AuthCookie.*|  |
                True     +------------------------------------+  |
                                              |                  |
               +--------------------+         |      +---------------+
               |                    |         |      | If we had a   |
               V                    |         V      | cookie, add   |
  +----------------------------+  r |         ^      | a Set-Cookie  |
  | If we didn't have a session|  e |T       / \     | header to     |
  | key cookie, add a          |  t |r      /   \    | override the  |
  | Set-Cookie header with this|  u |u     /     \   | invalid cookie|
  | session key. Client then   |  r |e    /       \  +---------------+
  | returns session key with   |  n |    /  pass   \               ^    
  | successive requests        |    |   /  session  \              |
  +----------------------------+    |  /   key to    \    return   |
               |                    +-| authen_ses_key|------------+
               V                       \             /     False
  +-----------------------------------+ \           /
  | Tell Apache to set Expires header,|  \         /
  | set user to user ID returned by   |   \       /
  | authen_ses_key, set authentication|    \     /
  | to our type (e.g. AuthCookie).    |     \   /
  +-----------------------------------+      \ /
                                              V
         (---------------------)              ^
         ( Request a protected )              |
         ( page, user has a    )--------------+
         ( session key cookie  )
         (---------------------)


 *  The session key that the client gets can be anything you want.  For
    example, encrypted information about the user, a hash of the
    username and password (similar in function to Digest
    authentication), or the user name and password in plain text
    (similar in function to HTTP Basic authentication).

    The only requirement is that the authen_ses_key function that you
    create must be able to determine if this session_key is valid and
    map it back to the originally authenticated user ID.

=for html
</PRE>

=head1 METHODS

C<Apache2_4::AuthCookie> has several methods you should know about.

=over 4

=item * authenticate()

This method is one you'll use in a server config file (httpd.conf, .htaccess,
...) as a PerlAuthenHandler.  If the user provided a session key in a cookie,
the C<authen_ses_key()> method will get called to check whether the key is
valid.  If not, or if there is no key provided, we redirect to the login form.

=item * authen_cred()

You must define this method yourself in your subclass of
C<Apache2_4::AuthCookie>.  Its job is to create the session key that will be
preserved in the user's cookie.  The arguments passed to it are:

 sub authen_cred ($$\@) {
     my $self = shift;  # Package name (same as AuthName directive)
     my $r    = shift;  # Apache request object
     my @cred = @_;     # Credentials from login form

     ...blah blah blah, create a session key...
     return $session_key;
 }

The only limitation on the session key is that you should be able to look at it
later and determine the user's username.  You are responsible for implementing
your own session key format.  A typical format is to make a string that
contains the username, an expiration time, whatever else you need, and an MD5
hash of all that data together with a secret key.  The hash will ensure that
the user doesn't tamper with the session key.

=item * authen_ses_key()

You must define this method yourself in your subclass of
C<Apache2_4::AuthCookie>.  Its job is to look at a session key and determine
whether it is valid.  If so, it returns the username of the authenticated user.

 sub authen_ses_key ($$$) {
     my ($self, $r, $session_key) = @_;
     ...blah blah blah, check whether $session_key is valid...
     return $ok ? $username : undef;
 }

Optionally, return an array of 2 or more items that will be passed to method
custom_errors. It is the responsibility of this method to return the correct
response to the main Apache module.

=item * custom_errors($r,@_)

This method handles the server response when you wish to access the Apache
custom_response method. Any suitable response can be used. this is
particularly useful when implementing 'by directory' access control using
the user authentication information. i.e.

        /restricted
                /one            user is allowed access here
                /two            not here
                /three          AND here

The authen_ses_key method would return a normal response when the user attempts
to access 'one' or 'three' but return (NOT_FOUND, 'File not found') if an
attempt was made to access subdirectory 'two'. Or, in the case of expired
credentials, (AUTH_REQUIRED,'Your session has timed out, you must login
again').

  example 'custom_errors'

  sub custom_errors {
      my ($self,$r,$CODE,$msg) = @_;

      # return custom message else use the server's standard message
      $r->custom_response($CODE, $msg) if $msg;

      return($CODE);
  }

  where CODE is a valid code from Apache2::Const

=item * login()

This method handles the submission of the login form.  It will call the
C<authen_cred()> method, passing it C<$r> and all the submitted data with names
like C<"credential_#">, where # is a number.  These will be passed in a simple
array, so the prototype is C<$self-E<gt>authen_cred($r, @credentials)>.  After
calling C<authen_cred()>, we set the user's cookie and redirect to the URL
contained in the C<"destination"> submitted form field.

=item * login_form($r)

This method is responsible for displaying the login form. The default
implementation will make an internal redirect and display the URL you specified
with the C<PerlSetVar WhatEverLoginScript> configuration directive. You can
overwrite this method to provide your own mechanism.

=item * login_form_status($r)

This method returns the HTTP status code that will be returned with the login
form response.  The default behaviour is to return HTTP_FORBIDDEN, except for
some known browsers which ignore HTML content for HTTP_FORBIDDEN responses
(e.g.: SymbianOS).  You can override this method to return custom codes.

Note that HTTP_FORBIDDEN is the most correct code to return as the given
request was not authorized to view the requested page.  You should only change
this if HTTP_FORBIDDEN does not work.

=item * logout()

This is simply a convenience method that unsets the session key for you.  You
can call it in your logout scripts.  Usually this looks like
C<$r-E<gt>auth_type-E<gt>logout($r);>.

=item * send_cookie($r, $session_key)

By default this method simply sends out the session key you give it.  If you
need to change the default behavior (perhaps to update a timestamp in the key)
you can override this method.

=item * recognize_user()

If the user has provided a valid session key but the document isn't protected,
this method will set C<$r-E<gt>user> anyway.  Use it as a PerlFixupHandler,
unless you have a better idea.

=item * key($r)

This method will return the current session key, if any.  This can be handy
inside a method that implements a C<require> directive check (like the
C<species> method discussed above) if you put any extra information like
clearances or whatever into the session key.

=item * untaint_destination($self, $uri)

This method returns a modified version of the destination parameter before
embedding it into the response header. Per default it escapes CR, LF and TAB
characters of the uri to avoid certain types of security attacks. You can
override it to more limit the allowed destinations, e.g., only allow relative
uris, only special hosts or only limited set of characters.

=back

=head1 EXAMPLE

For an example of how to use C<Apache2_4::AuthCookie>, you may want to check
out the test suite, which runs AuthCookie through a few of its paces.  The
documents are located in t/eg/, and you may want to peruse t/real.t to see the
generated httpd.conf file (at the bottom of real.t) and check out what requests
it's making of the server (at the top of real.t).

=head1 THE LOGIN SCRIPT

You will need to create a login script (called login.pl above) that generates
an HTML form for the user to fill out.  You might generate the page using a
ModPerl::Registry script, a HTML::Mason component, an Apache handler, or
perhaps even using a static HTML page.  It's usually useful to generate it
dynamically so that you can define the 'destination' field correctly (see
below).

The following fields must be present in the form:

=over 4

=item 1.

The ACTION of the form must be /LOGIN (or whatever you defined in your
server configuration as handled by the C<-E<gt>login()> method - see example in
the SYNOPSIS section).

=item 2.

The various user input fields (username, passwords, etc.) must be named
'credential_0', 'credential_1', etc. on the form.  These will get passed to
your C<authen_cred()> method.

=item 3.

You must define a form field called 'destination' that tells AuthCookie where
to redirect the request after successfully logging in.  Typically this value is
obtained from C<$r-E<gt>prev-E<gt>uri>.  See the login.pl script in t/eg/.

=back

In addition, you might want your login page to be able to tell why the user is
being asked to log in.  In other words, if the user sent bad credentials, then
it might be useful to display an error message saying that the given username
or password are invalid.  Also, it might be useful to determine the difference
between a user that sent an invalid auth cookie, and a user that sent no auth
cookie at all.  To cope with these situations, B<AuthCookie> will set
C<$r-E<gt>subprocess_env('AuthCookieReason')> to one of the following values.

=over 4

=item I<no_cookie>

The user presented no cookie at all.  Typically this means the user is
trying to log in for the first time.

=item I<bad_cookie>

The cookie the user presented is invalid.  Typically this means that the user
is not allowed access to the given page.

=item I<bad_credentials>

The user tried to log in, but the credentials that were passed are invalid.

=back

You can examine this value in your login form by examining
C<$r-E<gt>prev-E<gt>subprocess_env('AuthCookieReason')> (because it's a
sub-request).

Of course, if you want to give more specific information about why access
failed when a cookie is present, your C<authen_ses_key()> method can set
arbitrary entries in C<$r-E<gt>subprocess_env>.

=head1 THE LOGOUT SCRIPT

If you want to let users log themselves out (something that can't be done using
Basic Auth), you need to create a logout script.  For an example, see
t/htdocs/docs/logout.pl.  Logout scripts may want to take advantage of
AuthCookie's C<logout()> method, which will set the proper cookie headers in
order to clear the user's cookie.  This usually looks like
C<$r-E<gt>auth_type-E<gt>logout($r);>.

Note that if you don't necessarily trust your users, you can't count on cookie
deletion for logging out.  You'll have to expire some server-side login
information too.  AuthCookie doesn't do this for you, you have to handle it
yourself.

=head1 ABOUT SESSION KEYS

Unlike the sample AuthCookieHandler, you have you verify the user's login and
password in C<authen_cred()>, then you do something like:

    my $date = localtime;
    my $ses_key = Digest::SHA::sha256_hex(join(';', $date, $PID, $PAC));

save C<$ses_key> along with the user's login, and return C<$ses_key>.

Now C<authen_ses_key()> looks up the C<$ses_key> passed to it and returns the
saved login.  I use a database to store the session key and retrieve it later.

=head1 FREQUENTLY ASKED QUESTIONS

=over 4

=item *

I upgraded to Apache 2.4 and now AuthCookie doesn't work!

Apache 2.4 radically changed the authenciation and authorization API.  You will
need to port your AuthCookie subclass over to the Apache 2.4 API.  See the POD
documenation in L<README.apache-2.4> for more information, but the quick
rundown is you need to:

=over 4

=item *

Inherit from C<Apache2_4::AuthCookie>

=item *

Remove all C<PerlAuthzHandler> configuration entries.

=item *

Write Authz Provider methods for any C<Requires> directives that you are using
that apache does not provide for already (e.g. apache already handles C<user>
and C<valid-user>) and register them with something like.

 PerlAddAuthzProvier species Sample::AuthCookieHandler->authz_species

=item *

Replace instances of C<${AuthName}Satistfy> with either C<RequireAll> or
C<RequireAny> blocks.

=back

=item *

Why is my authz method called twice per request?

This is normal behaviour under Apache 2.4.  This is to accommodate for
authorization of anonymous access. You are expected to return
C<Apache2::Const::AUTHZ_DENIED_NO_USER> IF C<< $r->user >> has not yet been set
if you want authentication to proceed.  Your authz handler will be called a
second time after the user has been authenticated.

=item *

AuthCookie authenticates, but the authorization handler is returning
C<UNAUTHORIZED> instead of C<FORBIDDEN>!

In Apache 2.4, in C<mod_authz_core>, if no authz handlers return C<AUTHZ_GRANTED>,
then C<HTTP_UNAUTHORIZED> is returned.  In previous versions of Apache,
C<HTTP_FORBIDDEN> was returned.  You can get the old behaviour if you want it
with:

 AuthzSendForbiddenOnFailure On


=item *

My log shows an entry like:

 authorization result of Require ...: denied (no authenticated user yet)

These are normal.  This happens because the authz provider returned
C<AUTHZ_DENIED_NO_USER> and the authz provider will be called again after
authentication happens.

=back

=head1 HISTORY

Originally written by Eric Bartley <bartley@purdue.edu>

versions 2.x were written by Ken Williams <ken@forum.swarthmore.edu>

=head1 COPYRIGHT

Copyright (c) 2015 Michael Schout. All rights reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

L<perl(1)>, L<mod_perl(1)>, L<Apache(1)>.

=cut

# vim: sw=4 ts=4 ai et
