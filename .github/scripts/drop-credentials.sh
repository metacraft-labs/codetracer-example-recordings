# Source this before any step that RECORDS a program:
#
#   . .github/scripts/drop-credentials.sh || exit 1
#
# A recording captures the recorded process's environment (its stack's envp
# and the `guest.env` member), and the recorded process inherits the
# recorder's. In a CI job that environment holds credentials: the git
# extraheader setup actions leave in GIT_CONFIG_* (an `AUTHORIZATION: basic`
# header carrying an installation token), and whatever token variables a step
# defines. A fixture recorded with them published a live token on 2026-10-03.
#
# This unsets every such variable in the current shell, then refuses to go on
# if any value left still looks like a credential, so a new kind of variable
# fails the step instead of reaching a recording. It is one layer: the
# regenerate scripts also record under `env -i`, and verify-recordings.sh
# scans what was produced.

# Git configuration passed through the environment (GIT_CONFIG_COUNT and its
# numbered KEY/VALUE pairs) and every variable named like a credential.
for _ct_var in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p'); do
	case "$_ct_var" in
	GIT_CONFIG_COUNT | GIT_CONFIG_KEY_* | GIT_CONFIG_VALUE_* | GIT_CONFIG_PARAMETERS | \
		GIT_ASKPASS | SSH_AUTH_SOCK | \
		ACTIONS_RUNTIME_TOKEN | ACTIONS_ID_TOKEN_REQUEST_* | ACTIONS_CACHE_URL | ACTIONS_RESULTS_URL | \
		AWS_* | MCL_S3_* | ATTIC_* | \
		*TOKEN* | *SECRET* | *PASSWORD* | *PASSWD* | *CREDENTIAL* | *_KEY | *_KEY_ID | *PRIVATE*)
		unset "$_ct_var"
		;;
	esac
done
unset _ct_var

# Anything still credential-shaped is a variable this list does not know.
if env | grep -E -i -q 'authorization: *(basic|bearer|token) |x-access-token:|gh[pousr]_[A-Za-z0-9]{36}|github_pat_|(^|[^A-Za-z0-9])A[KS]IA[A-Z0-9]{16}|PRIVATE KEY-----'; then
	echo "::error title=Credential left in the environment::a credential-shaped value survived drop-credentials.sh; refusing to record. Variables (values withheld):" >&2
	env | grep -E -i 'authorization: *(basic|bearer|token) |x-access-token:|gh[pousr]_[A-Za-z0-9]{36}|github_pat_|(^|[^A-Za-z0-9])A[KS]IA[A-Z0-9]{16}|PRIVATE KEY-----' |
		sed 's/=.*//' | sed 's/^/  /' >&2
	return 1
fi
