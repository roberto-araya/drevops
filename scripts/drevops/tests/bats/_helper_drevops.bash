#!/usr/bin/env bash
#
# Helpers related to DrevOps common testing functionality.
#
# shellcheck disable=SC2155

load "${BASH_SOURCE[0]%/*}"/_mock.bash

################################################################################
#                          HOOK IMPLEMENTATIONS                                #
################################################################################

# To run installation tests, several fixture directories are required. They are
# defined and created in setup() test method.
#
# $BUILD_DIR - root build directory where the rest of fixture directories located.
# The "build" in this context is a place to store assets produce by the install
# script during the test.
#
# $CURRENT_PROJECT_DIR - directory where install script is executed. May have
# existing project files (e.g. from previous installations) or be empty (to
# facilitate brand-new install).
#
# $DST_PROJECT_DIR - directory where DrevOps may be installed to. By default,
# install uses $CURRENT_PROJECT_DIR as a destination, but we use
# $DST_PROJECT_DIR to test a scenario where different destination is provided.
#
# $LOCAL_REPO_DIR - directory where install script will be sourcing the instance
# of DrevOps.
#
# $APP_TMP_DIR - directory where the application may store it's temporary files.
setup() {
  export DREVOPS_DRUPAL_VERSION="${DREVOPS_DRUPAL_VERSION:-9}"
  export CUR_DIR="$(pwd)"
  export BUILD_DIR="${BUILD_DIR:-"${BATS_TEST_TMPDIR}/drevops-$(random_string)"}"

  export CURRENT_PROJECT_DIR="${BUILD_DIR}/star_wars"
  export DST_PROJECT_DIR="${BUILD_DIR}/dst"
  export LOCAL_REPO_DIR="${BUILD_DIR}/local_repo"
  export APP_TMP_DIR="${BUILD_DIR}/tmp"
  export DREVOPS_TEST_ARTIFACT_DIR="/app/tests/behat"
  export DREVOPS_TEST_REPORTS_DIR="/app/test_reports"
  export DREVOPS_AHOY_CONFIRM_RESPONSE=y

  export DREVOPS_INSTALL_DEMO_DB_TEST=https://raw.githubusercontent.com/wiki/drevops/drevops/db_d9.star_wars.sql.md

  # Unset any environment variables that may affect tests.
  # These are set in CI config to override values set in .env file for some jobs.
  unset DREVOPS_DB_DOWNLOAD_SOURCE
  unset DREVOPS_DB_DOCKER_IMAGE
  unset DREVOPS_DB_DOWNLOAD_FORCE

  # Disable checks used on host machine.
  export DREVOPS_DOCTOR_CHECK_TOOLS=0
  export DREVOPS_DOCTOR_CHECK_PYGMY=0
  export DREVOPS_DOCTOR_CHECK_PORT=0
  export DREVOPS_DOCTOR_CHECK_SSH=0
  export DREVOPS_DOCTOR_CHECK_WEBSERVER=0
  export DREVOPS_DOCTOR_CHECK_BOOTSTRAP=0

  prepare_fixture_dir "${BUILD_DIR}"
  prepare_fixture_dir "${CURRENT_PROJECT_DIR}"
  prepare_fixture_dir "${DST_PROJECT_DIR}"
  prepare_fixture_dir "${LOCAL_REPO_DIR}"
  prepare_fixture_dir "${APP_TMP_DIR}"
  prepare_local_repo "${LOCAL_REPO_DIR}" >/dev/null
  prepare_global_gitconfig
  prepare_global_gitignore

  echo "BUILD_DIR dir: ${BUILD_DIR}" >&3

  # Setup command mocking.
  setup_mock

  # Change directory to the current project directory for each test. Tests
  # requiring to operate outside of CURRENT_PROJECT_DIR (like deployment tests)
  # should change directory explicitly within their tests.
  pushd "${CURRENT_PROJECT_DIR}" >/dev/null || exit 1
}

teardown() {
  restore_global_gitignore
  popd >/dev/null || cd "${CUR_DIR}" || exit 1
}

################################################################################
#                            COMMAND MOCKING                                   #
################################################################################

# Setup mock support.
# Call this function from your test's setup() method.
setup_mock() {
  # Command and functions mocking support.
  # @see https://github.com/grayhemp/bats-mock
  #
  # Prepare directory with mock binaries, get it's path, and export it so that
  # bats-mock could use it internally.
  BATS_MOCK_TMPDIR="$(mock_prepare_tmp)"
  export "BATS_MOCK_TMPDIR"
  # Set the path to temp mocked binaries directory as the first location in
  # PATH to lookup in mock directories first. This change lives only for the
  # duration of the test and will be reset after. It does not modify the PATH
  # outside of the running test.
  PATH="${BATS_MOCK_TMPDIR}:$PATH"
}

# Prepare temporary mock directory.
mock_prepare_tmp() {
  rm -rf "${BATS_TMPDIR}/bats-mock-tmp" >/dev/null
  mkdir -p "${BATS_TMPDIR}/bats-mock-tmp"
  echo "${BATS_TMPDIR}/bats-mock-tmp"
}

# Mock provided command.
# Arguments:
#  1. Mocked command name,
# Outputs:
#   STDOUT: path to created mock file.
mock_command() {
  mocked_command="${1}"
  mock="$(mock_create)"
  mock_path="${mock%/*}"
  mock_file="${mock##*/}"
  ln -sf "${mock_path}/${mock_file}" "${mock_path}/${mocked_command}"
  echo "$mock"
}

################################################################################
#                               ASSERTIONS                                     #
################################################################################

assert_files_present() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"
  local suffix_abbreviated="${3:-sw}"
  local suffix_abbreviated_camel_cased="${4:-Sw}"

  assert_files_present_common "${dir}" "${suffix}" "${suffix_abbreviated}" "${suffix_abbreviated_camel_cased}"

  assert_files_local_present "${dir}"

  # Assert Drupal profile not present by default.
  assert_files_present_no_profile "${dir}" "${suffix}"

  # Assert Drupal is not installed from the profile by default.
  assert_files_present_no_install_from_profile "${dir}" "${suffix}"

  # Assert Drupal is not set to override an existing DB by default.
  assert_files_present_no_override_existing_db "${dir}" "${suffix}"

  # Assert deployments preserved.
  assert_files_present_deployment "${dir}" "${suffix}"

  # Assert Acquia integration is not preserved.
  assert_files_present_no_integration_acquia "${dir}" "${suffix}"

  # Assert Lagoon integration is not preserved.
  assert_files_present_no_integration_lagoon "${dir}" "${suffix}"

  # Assert FTP integration removed by default.
  assert_files_present_no_integration_ftp "${dir}" "${suffix}"

  # Assert renovatebot.com integration preserved.
  assert_files_present_integration_renovatebot "${dir}" "${suffix}"
}

assert_files_local_present() {
  local dir="${1:-$(pwd)}"

  pushd "${dir}" >/dev/null || exit 1
  assert_file_exists ".env.local"
  popd >/dev/null || exit 1
}

assert_files_present_common() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"
  local suffix_abbreviated="${3:-sw}"
  local suffix_abbreviated_camel_cased="${4:-Sw}"

  pushd "${dir}" >/dev/null || exit 1

  # Default DrevOps files present.
  assert_files_present_drevops "${dir}"

  # Assert that project name is correct.
  assert_file_contains .env "DREVOPS_PROJECT=${suffix}"
  assert_file_contains .env "DREVOPS_LOCALDEV_URL=${suffix/_/-}.docker.amazee.io"

  # Assert that DrevOps version was replaced.
  assert_file_contains "README.md" "badge/DrevOps-${DREVOPS_DRUPAL_VERSION}.x-blue.svg"
  assert_file_contains "README.md" "https://github.com/drevops/drevops/tree/${DREVOPS_DRUPAL_VERSION}.x"

  assert_files_present_drupal "${dir}" "${suffix}" "${suffix_abbreviated}" "${suffix_abbreviated_camel_cased}"

  popd >/dev/null || exit 1
}

# These files should exist in every project.
assert_files_present_drevops() {
  local dir="${1:-$(pwd)}"

  pushd "${dir}" >/dev/null || exit 1

  assert_file_exists ".circleci/config.yml"

  assert_file_exists ".docker/Dockerfile.cli"
  assert_file_exists ".docker/Dockerfile.mariadb"
  assert_file_exists ".docker/Dockerfile.nginx-drupal"
  assert_file_exists ".docker/Dockerfile.php"
  assert_file_exists ".docker/Dockerfile.solr"
  assert_file_exists ".docker/scripts/.gitkeep"
  assert_file_exists ".docker/config/mariadb/my.cnf"
  assert_file_exists ".docker/config/solr/elevate.xml"
  assert_file_exists ".docker/config/solr/schema.xml"
  assert_file_exists ".docker/config/solr/solrconfig.xml"
  assert_file_exists ".docker/config/solr/solrcore.properties"

  assert_file_exists ".github/PULL_REQUEST_TEMPLATE.md"

  assert_dir_exists "config/ci"
  assert_dir_exists "config/default"
  assert_dir_exists "config/dev"
  assert_dir_exists "config/local"
  assert_dir_exists "config/test"

  assert_file_exists "patches/.gitkeep"

  assert_file_exists "scripts/composer/DrupalSettings.php"
  assert_file_exists "scripts/composer/ScriptHandler.php"
  assert_file_exists "scripts/custom/.gitkeep"

  # Core DrevOps files.
  assert_file_exists "scripts/drevops/build.sh"
  assert_file_exists "scripts/drevops/clean.sh"
  assert_file_exists "scripts/drevops/deploy.sh"
  assert_file_exists "scripts/drevops/deploy-artifact.sh"
  assert_file_exists "scripts/drevops/deploy-docker.sh"
  assert_file_exists "scripts/drevops/deploy-lagoon.sh"
  assert_file_exists "scripts/drevops/deploy-webhook.sh"
  assert_file_exists "scripts/drevops/docker-login.sh"
  assert_file_exists "scripts/drevops/docker-restore-image.sh"
  assert_file_exists "scripts/drevops/doctor.sh"
  assert_file_exists "scripts/drevops/download-db.sh"
  assert_file_exists "scripts/drevops/download-db-acquia.sh"
  assert_file_exists "scripts/drevops/download-db-curl.sh"
  assert_file_exists "scripts/drevops/download-db-ftp.sh"
  assert_file_exists "scripts/drevops/download-db-image.sh"
  assert_file_exists "scripts/drevops/download-db-lagoon.sh"
  assert_file_exists "scripts/drevops/export-db-file.sh"
  assert_file_exists "scripts/drevops/export-db-docker.sh"
  assert_file_exists "scripts/drevops/drupal-install-site.sh"
  assert_file_exists "scripts/drevops/drupal-login.sh"
  assert_file_exists "scripts/drevops/drupal-sanitize-db.sh"
  assert_file_exists "scripts/drevops/export-code.sh"
  assert_file_exists "scripts/drevops/github-labels.sh"
  assert_file_exists "scripts/drevops/info.sh"
  assert_file_exists "scripts/drevops/lint.sh"
  assert_file_exists "scripts/drevops/notify-deployment-email.php"
  assert_file_exists "scripts/drevops/notify-deployment-github.sh"
  assert_file_exists "scripts/drevops/notify-deployment-jira.sh"
  assert_file_exists "scripts/drevops/notify-deployment-newrelic.sh"
  assert_file_exists "scripts/drevops/reset.sh"
  assert_file_exists "scripts/drevops/task-copy-db-acquia.sh"
  assert_file_exists "scripts/drevops/task-copy-files-acquia.sh"
  assert_file_exists "scripts/drevops/task-purge-cache-acquia.sh"
  assert_file_exists "scripts/drevops/test.sh"
  assert_file_exists "scripts/drevops/update.sh"

  assert_file_exists "scripts/sanitize.sql"

  assert_file_exists "tests/behat/bootstrap/FeatureContext.php"
  assert_dir_exists "tests/behat/features"
  assert_file_exists "tests/behat/fixtures/.gitkeep"

  assert_file_exists ".ahoy.yml"
  assert_file_exists ".dockerignore"
  assert_file_exists ".editorconfig"
  assert_file_exists ".env"
  assert_file_not_exists ".gitattributes"
  assert_file_exists ".gitignore"
  assert_file_exists "behat.yml"
  assert_file_exists "composer.json"
  assert_file_exists "default.ahoy.local.yml"
  assert_file_exists "default.docker-compose.override.yml"
  assert_file_exists "default.env.local"
  assert_file_exists "docker-compose.yml"
  assert_file_exists "phpcs.xml"

  # Documentation information present.
  assert_file_exists "CI.md"
  assert_file_exists "FAQs.md"
  assert_file_exists "README.md"
  assert_file_exists "RELEASING.md"
  assert_file_exists "TESTING.md"

  # Assert that DrevOps files removed.
  assert_file_not_exists "install.php"
  assert_file_not_exists "install.sh"
  assert_file_not_exists "LICENSE"
  assert_dir_not_exists "scripts/drevops/docs"
  assert_dir_not_exists "scripts/drevops/tests"
  assert_dir_not_exists "scripts/drevops/utils"
  assert_file_not_exists ".github/FUNDING.yml"
  assert_file_not_contains ".circleci/config.yml" "drevops_dev_test"
  assert_file_not_contains ".circleci/config.yml" "drevops_dev_test_workflow"
  assert_file_not_contains ".circleci/config.yml" "drevops_dev_test_deployment"
  assert_file_not_contains ".circleci/config.yml" "drevops_dev_deploy"
  assert_file_not_contains ".circleci/config.yml" "drevops_dev_deploy_tags"
  assert_file_not_contains ".circleci/config.yml" "drevops_dev_didi_database_fi"
  assert_file_not_contains ".circleci/config.yml" "drevops_dev_database_ii"
  assert_file_not_contains ".circleci/config.yml" "drevops_dev_didi_build_fi"
  assert_file_not_contains ".circleci/config.yml" "drevops_dev_didi_build_ii"
  assert_file_not_contains ".circleci/config.yml" "drevops_dev_docs"
  assert_file_not_contains ".circleci/config.yml" "drevops_dev_didi_fi"
  assert_file_not_contains ".circleci/config.yml" "drevops_dev_didi_ii"
  assert_file_not_contains ".circleci/config.yml" "drevops_dev_installer"

  # Assert that documentation was processed correctly.
  assert_file_not_contains README.md "# DrevOps"

  popd >/dev/null || exit 1
}

assert_files_present_drupal(){
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"
  local suffix_abbreviated="${3:-sw}"
  local suffix_abbreviated_camel_cased="${4:-Sw}"

  pushd "${dir}" >/dev/null || exit 1


  # Stub profile removed.
  assert_dir_not_exists "docroot/profiles/custom/your_site_profile"
  # Stub code module removed.
  assert_dir_not_exists "docroot/modules/custom/ys_core"
  # Stub theme removed.
  assert_dir_not_exists "docroot/themes/custom/your_site_theme"

  # Site core module created.
  assert_dir_exists "docroot/modules/custom/${suffix_abbreviated}_core"
  assert_file_exists "docroot/modules/custom/${suffix_abbreviated}_core/${suffix_abbreviated}_core.info.yml"
  assert_file_exists "docroot/modules/custom/${suffix_abbreviated}_core/${suffix_abbreviated}_core.install"
  assert_file_exists "docroot/modules/custom/${suffix_abbreviated}_core/${suffix_abbreviated}_core.module"
  assert_file_exists "docroot/modules/custom/${suffix_abbreviated}_core/tests/src/Unit/${suffix_abbreviated_camel_cased}CoreExampleUnitTest.php"
  assert_file_exists "docroot/modules/custom/${suffix_abbreviated}_core/tests/src/Unit/${suffix_abbreviated_camel_cased}CoreUnitTestBase.php"
  assert_file_exists "docroot/modules/custom/${suffix_abbreviated}_core/tests/src/Kernel/${suffix_abbreviated_camel_cased}CoreExampleKernelTest.php"
  assert_file_exists "docroot/modules/custom/${suffix_abbreviated}_core/tests/src/Kernel/${suffix_abbreviated_camel_cased}CoreKernelTestBase.php"
  assert_file_exists "docroot/modules/custom/${suffix_abbreviated}_core/tests/src/Functional/${suffix_abbreviated_camel_cased}CoreExampleFunctionalTest.php"
  assert_file_exists "docroot/modules/custom/${suffix_abbreviated}_core/tests/src/Functional/${suffix_abbreviated_camel_cased}CoreFunctionalTestBase.php"

  # Site theme created.
  assert_dir_exists "docroot/themes/custom/${suffix}"
  assert_file_exists "docroot/themes/custom/${suffix}/js/${suffix}.js"
  assert_dir_exists "docroot/themes/custom/${suffix}/scss"
  assert_dir_exists "docroot/themes/custom/${suffix}/images"
  assert_dir_exists "docroot/themes/custom/${suffix}/fonts"
  assert_file_exists "docroot/themes/custom/${suffix}/.gitignore"
  assert_file_exists "docroot/themes/custom/${suffix}/${suffix}.info.yml"
  assert_file_exists "docroot/themes/custom/${suffix}/${suffix}.libraries.yml"
  assert_file_exists "docroot/themes/custom/${suffix}/${suffix}.theme"
  assert_file_exists "docroot/themes/custom/${suffix}/Gruntfile.js"
  assert_file_exists "docroot/themes/custom/${suffix}/package.json"

  # Comparing binary files.
  assert_files_equal "${LOCAL_REPO_DIR}/docroot/themes/custom/your_site_theme/screenshot.png" "docroot/themes/custom/${suffix}/screenshot.png"

  # Drupal scaffolding files exist.
  assert_file_exists "docroot/.editorconfig"
  assert_file_exists "docroot/.eslintignore"
  assert_file_exists "docroot/.gitattributes"
  assert_file_exists "docroot/.htaccess"
  assert_file_exists "docroot/autoload.php"
  assert_file_exists "docroot/index.php"
  assert_file_exists "docroot/robots.txt"
  assert_file_exists "docroot/update.php"

  # Settings files exist.
  # @note The permissions can be 644 or 664 depending on the umask of OS. Also,
  # git only track 644 or 755.
  assert_file_exists "docroot/sites/default/settings.php"
  assert_file_mode "docroot/sites/default/settings.php" "644"

  assert_dir_exists "docroot/sites/default/includes/"

  assert_file_exists "docroot/sites/default/default.settings.php"
  assert_file_exists "docroot/sites/default/default.services.yml"

  assert_file_exists "docroot/sites/default/default.settings.local.php"
  assert_file_mode "docroot/sites/default/default.settings.local.php" "644"

  assert_file_exists "docroot/sites/default/default.services.local.yml"
  assert_file_mode "docroot/sites/default/default.services.local.yml" "644"

  # Special case to fix all occurrences of the stub in core files to exclude
  # false-positives from the assertions below.
  replace_core_stubs "${dir}" "your_site"

  # Assert all stub strings were replaced.
  assert_dir_not_contains_string "${dir}" "your_site"
  assert_dir_not_contains_string "${dir}" "ys_core"
  assert_dir_not_contains_string "${dir}" "YOURSITE"
  assert_dir_not_contains_string "${dir}" "YourSite"
  assert_dir_not_contains_string "${dir}" "your_site_theme"
  assert_dir_not_contains_string "${dir}" "your_org"
  assert_dir_not_contains_string "${dir}" "YOURORG"
  assert_dir_not_contains_string "${dir}" "your-site-url.example"
  # Assert all special comments were removed.
  assert_dir_not_contains_string "${dir}" "#;"
  assert_dir_not_contains_string "${dir}" "#;<"
  assert_dir_not_contains_string "${dir}" "#;>"

  popd >/dev/null || exit 1
}

assert_files_not_present_common() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-sw}"
  local suffix_abbreviated="${3:-sw}"
  local has_required_files="${3:-0}"

  pushd "${dir}" >/dev/null || exit 1

  assert_dir_not_exists "docroot/modules/custom/ys_core"
  assert_dir_not_exists "docroot/themes/custom/your_site_theme"
  assert_dir_not_exists "docroot/profiles/custom/${suffix}_profile"
  assert_dir_not_exists "docroot/modules/custom/${suffix_abbreviated}_core"
  assert_dir_not_exists "docroot/themes/custom/${suffix}"
  assert_file_not_exists "docroot/sites/default/default.settings.local.php"
  assert_file_not_exists "docroot/sites/default/default.services.local.yml"
  assert_file_not_exists "docroot/modules/custom/ys_core/tests/src/Unit/YourSiteExampleUnitTest.php"
  assert_file_not_exists "docroot/modules/custom/ys_core/tests/src/Unit/YourSiteCoreUnitTestBase.php"
  assert_file_not_exists "docroot/modules/custom/ys_core/tests/src/Kernel/YourSiteExampleKernelTest.php"
  assert_file_not_exists "docroot/modules/custom/ys_core/tests/src/Kernel/YourSiteCoreKernelTestBase.php"
  assert_file_not_exists "docroot/modules/custom/ys_core/tests/src/Functional/YourSiteExampleFunctionalTest.php"
  assert_file_not_exists "docroot/modules/custom/ys_core/tests/src/Functional/YourSiteCoreFunctionalTestBase.php"

  assert_file_not_exists "FAQs.md"
  assert_file_not_exists ".ahoy.yml"

  if [ "${has_required_files}" -eq 1 ]; then
    assert_file_exists "README.md"
    assert_file_exists ".circleci/config.yml"
    assert_file_exists "docroot/sites/default/settings.php"
    assert_file_exists "docroot/sites/default/services.yml"
  else
    assert_file_not_exists "README.md"
    assert_file_not_exists ".circleci/config.yml"
    assert_file_not_exists "docroot/sites/default/settings.php"
    assert_file_not_exists "docroot/sites/default/services.yml"
    # Scaffolding files not exist.
    assert_file_not_exists "docroot/.editorconfig"
    assert_file_not_exists "docroot/.eslintignore"
    assert_file_not_exists "docroot/.gitattributes"
    assert_file_not_exists "docroot/.htaccess"
    assert_file_not_exists "docroot/autoload.php"
    assert_file_not_exists "docroot/index.php"
    assert_file_not_exists "docroot/robots.txt"
    assert_file_not_exists "docroot/update.php"
  fi

  popd >/dev/null || exit 1
}

assert_files_present_profile() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"

  pushd "${dir}" >/dev/null || exit 1

  # Site profile created.
  assert_dir_exists "docroot/profiles/custom/${suffix}_profile"
  assert_file_exists "docroot/profiles/custom/${suffix}_profile/${suffix}_profile.info.yml"
  assert_file_contains ".env" "DREVOPS_DRUPAL_PROFILE="
  assert_file_contains ".env" "docroot/profiles/custom/${suffix}_profile,"

  popd >/dev/null || exit 1
}

assert_files_present_no_profile() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"

  pushd "${dir}" >/dev/null || exit 1

  # Site profile created.
  assert_dir_not_exists "docroot/profiles/custom/${suffix}_profile"
  assert_file_contains ".env" "DREVOPS_DRUPAL_PROFILE=standard"
  assert_file_not_contains ".env" "docroot/profiles/custom/${suffix}_profile,"
  # Assert that there is no renaming of the custom profile with core profile name.
  assert_dir_not_exists "docroot/profiles/custom/standard"
  assert_file_not_contains ".env" "docroot/profiles/custom/standard,"

  popd >/dev/null || exit 1
}

assert_files_present_install_from_profile() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"

  pushd "${dir}" >/dev/null || exit 1

  assert_file_contains ".env" "DREVOPS_DRUPAL_INSTALL_FROM_PROFILE=1"
  assert_file_not_contains ".env" "DREVOPS_DB_DOWNLOAD_SOURCE"
  assert_file_not_contains ".env" "DREVOPS_DB_DOWNLOAD_CURL_URL"
  assert_file_not_contains ".env" "DREVOPS_DB_DOWNLOAD_LAGOON_ENVIRONMENT"

  assert_file_not_contains "default.env.local" "DREVOPS_DB_DOWNLOAD_FORCE"
  assert_file_not_contains "default.env.local" "DREVOPS_DB_DOWNLOAD_FTP_USER"
  assert_file_not_contains "default.env.local" "DREVOPS_DB_DOWNLOAD_FTP_PASS"
  assert_file_not_contains "default.env.local" "DREVOPS_ACQUIA_KEY"
  assert_file_not_contains "default.env.local" "DREVOPS_ACQUIA_SECRET"
  assert_file_not_contains "default.env.local" "DREVOPS_DB_DOWNLOAD_SSH_KEY_FILE"
  assert_file_not_contains "default.env.local" "DREVOPS_DOCKER_REGISTRY_USERNAME"
  assert_file_not_contains "default.env.local" "DREVOPS_DOCKER_REGISTRY_TOKEN"

  assert_file_exists ".ahoy.yml"
  assert_file_not_contains ".ahoy.yml" "download-db:"

  assert_file_not_contains "README.md" "ahoy download-db"

  assert_file_not_contains ".circleci/config.yml" "db_ssh_fingerprint"
  assert_file_not_contains ".circleci/config.yml" "drevops_ci_db_cache_timestamp"
  assert_file_not_contains ".circleci/config.yml" "drevops_ci_db_cache_fallback"
  assert_file_not_contains ".circleci/config.yml" "drevops_ci_db_cache_branch"
  assert_file_not_contains ".circleci/config.yml" "db_cache_dir"
  assert_file_not_contains ".circleci/config.yml" "nightly_db_schedule"
  assert_file_not_contains ".circleci/config.yml" "nightly_db_branch"
  assert_file_not_contains ".circleci/config.yml" "DREVOPS_DB_DOWNLOAD_SSH_FINGERPRINT"
  assert_file_not_contains ".circleci/config.yml" "DREVOPS_CI_DB_CACHE_TIMESTAMP"
  assert_file_not_contains ".circleci/config.yml" "DREVOPS_CI_DB_CACHE_FALLBACK"
  assert_file_not_contains ".circleci/config.yml" "DREVOPS_CI_DB_CACHE_BRANCH"
  assert_file_not_contains ".circleci/config.yml" "database: &job_database"
  assert_file_not_contains ".circleci/config.yml" "database_nightly"
  assert_file_not_contains ".circleci/config.yml" "name: Set cache keys for database caching"
  assert_file_not_contains ".circleci/config.yml" "- database:"

  popd >/dev/null || exit 1
}

assert_files_present_no_install_from_profile() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"

  pushd "${dir}" >/dev/null || exit 1

  assert_file_contains ".env" "DREVOPS_DRUPAL_INSTALL_FROM_PROFILE=0"

  assert_file_exists ".ahoy.yml"
  assert_file_contains ".ahoy.yml" "download-db:"

  assert_file_contains "README.md" "ahoy download-db"

  assert_file_contains ".circleci/config.yml" "db_ssh_fingerprint"
  assert_file_contains ".circleci/config.yml" "drevops_ci_db_cache_timestamp"
  assert_file_contains ".circleci/config.yml" "drevops_ci_db_cache_fallback"
  assert_file_contains ".circleci/config.yml" "drevops_ci_db_cache_branch"
  assert_file_contains ".circleci/config.yml" "db_cache_dir"
  assert_file_contains ".circleci/config.yml" "nightly_db_schedule"
  assert_file_contains ".circleci/config.yml" "nightly_db_branch"
  assert_file_contains ".circleci/config.yml" "DREVOPS_DB_DOWNLOAD_SSH_FINGERPRINT"
  assert_file_contains ".circleci/config.yml" "DREVOPS_CI_DB_CACHE_TIMESTAMP"
  assert_file_contains ".circleci/config.yml" "DREVOPS_CI_DB_CACHE_FALLBACK"
  assert_file_contains ".circleci/config.yml" "DREVOPS_CI_DB_CACHE_BRANCH"
  assert_file_contains ".circleci/config.yml" "database: &job_database"
  assert_file_contains ".circleci/config.yml" "database_nightly"
  assert_file_contains ".circleci/config.yml" "name: Set cache keys for database caching"
  assert_file_contains ".circleci/config.yml" "- database:"

  popd >/dev/null || exit 1
}

assert_files_present_override_existing_db(){
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"

  pushd "${dir}" >/dev/null || exit 1

  assert_file_contains ".env" "DREVOPS_DRUPAL_INSTALL_OVERRIDE_EXISTING_DB=1"

  popd >/dev/null || exit 1
}

assert_files_present_no_override_existing_db(){
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"

  pushd "${dir}" >/dev/null || exit 1

  assert_file_contains ".env" "DREVOPS_DRUPAL_INSTALL_OVERRIDE_EXISTING_DB=0"

  popd >/dev/null || exit 1
}

assert_files_present_deployment() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"

  pushd "${dir}" >/dev/null || exit 1

  assert_file_exists "DEPLOYMENT.md"
  assert_file_contains ".circleci/config.yml" "deploy: &job_deploy"
  assert_file_contains ".circleci/config.yml" "deploy_tags: &job_deploy_tags"
  assert_file_contains "README.md" "[deployment documentation](DEPLOYMENT.md)"

  popd >/dev/null || exit 1
}

assert_files_present_no_deployment() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"
  local has_committed_files="${3:-0}"

  pushd "${dir}" >/dev/null || exit 1

  assert_file_not_exists ".gitignore.deployment"
  assert_file_not_exists "DEPLOYMENT.md"

  # 'Required' files can be asserted for modifications only if they were not
  # committed.
  if [ "${has_committed_files}" -eq 0 ]; then
    assert_file_not_contains "README.md" "[deployment documentation](DEPLOYMENT.md)"
    assert_file_not_contains ".circleci/config.yml" "deploy: &job_deploy"
    assert_file_not_contains ".circleci/config.yml" "deploy_tags: &job_deploy_tags"
    assert_file_not_contains ".circleci/config.yml" "- deploy:"
    assert_file_not_contains ".circleci/config.yml" "- deploy_tags:"
  fi

  popd >/dev/null || exit 1
}

assert_files_present_integration_acquia() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-sw}"
  local include_scripts="${3:-1}"

  pushd "${dir}" >/dev/null || exit 1

  assert_dir_exists "hooks"
  assert_dir_exists "hooks/library"
  assert_file_mode "hooks/library/copy-db.sh" "755"
  assert_file_mode "hooks/library/copy-files.sh" "755"
  assert_file_mode "hooks/library/install-site.sh" "755"
  assert_file_mode "hooks/library/notify-deployment-email.sh" "755"
  assert_file_mode "hooks/library/notify-deployment-newrelic.sh" "755"
  assert_file_mode "hooks/library/purge-cache.sh" "755"

  assert_dir_exists "hooks/common"
  assert_dir_exists "hooks/common/post-code-update"
  assert_symlink_exists "hooks/common/post-code-update/1.install-site.sh"
  assert_symlink_exists "hooks/common/post-code-update/2.purge-cache.sh"
  assert_symlink_exists "hooks/common/post-code-update/3.notify-deployment-email.sh"
  assert_symlink_exists "hooks/common/post-code-deploy"
  assert_symlink_exists "hooks/common/post-db-copy/1.install-site.sh"
  assert_symlink_exists "hooks/common/post-db-copy/2.purge-cache.sh"
  assert_symlink_exists "hooks/common/post-db-copy/3.notify-deployment-email.sh"

  assert_dir_exists "hooks/prod"
  assert_dir_exists "hooks/prod/post-code-deploy"
  assert_symlink_exists "hooks/prod/post-code-update"
  assert_symlink_not_exists "hooks/prod/post-db-copy"
  assert_symlink_exists "hooks/prod/post-code-update/1.notify-deployment-newrelic.sh"

  assert_file_contains "docroot/sites/default/settings.php" "if (file_exists('/var/www/site-php"
  assert_file_contains "docroot/.htaccess" "RewriteCond %{ENV:AH_SITE_ENVIRONMENT} prod [NC]"

  if [ "${include_scripts}" -eq 1 ]; then
    assert_dir_exists "scripts"
    assert_file_contains ".env" "DREVOPS_ACQUIA_APP_NAME="
    assert_file_contains ".env" "DREVOPS_DB_DOWNLOAD_ACQUIA_ENV="
    assert_file_contains ".env" "DREVOPS_DB_DOWNLOAD_ACQUIA_DB_NAME="
  fi

  popd >/dev/null || exit 1
}

assert_files_present_no_integration_acquia() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"

  pushd "${dir}" >/dev/null || exit 1

  assert_dir_not_exists "hooks"
  assert_dir_not_exists "hooks/library"
  assert_file_not_contains "docroot/sites/default/settings.php" "if (file_exists('/var/www/site-php')) {"
  assert_file_not_contains "docroot/.htaccess" "RewriteCond %{ENV:AH_SITE_ENVIRONMENT} prod [NC]"
  assert_file_not_contains ".env" "DREVOPS_ACQUIA_APP_NAME="
  assert_file_not_contains ".env" "DREVOPS_DB_DOWNLOAD_ACQUIA_ENV="
  assert_file_not_contains ".env" "DREVOPS_DB_DOWNLOAD_ACQUIA_DB_NAME="
  assert_file_not_contains ".ahoy.yml" "DREVOPS_ACQUIA_APP_NAME="
  assert_file_not_contains ".ahoy.yml" "DREVOPS_DB_DOWNLOAD_ACQUIA_ENV="
  assert_file_not_contains ".ahoy.yml" "DREVOPS_DB_DOWNLOAD_ACQUIA_DB_NAME="
  assert_dir_not_contains_string "${dir}" "DREVOPS_ACQUIA_KEY"
  assert_dir_not_contains_string "${dir}" "DREVOPS_ACQUIA_SECRET"

  popd >/dev/null || exit 1
}

assert_files_present_integration_lagoon() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"

  pushd "${dir}" >/dev/null || exit 1

  assert_file_exists ".lagoon.yml"
  assert_file_exists "drush/aliases.drushrc.php"
  assert_file_exists ".github/workflows/dispatch-webhook-lagoon.yml"
  assert_file_contains "docker-compose.yml" "labels"
  assert_file_contains "docker-compose.yml" "lagoon.type: cli-persistent"
  assert_file_contains "docker-compose.yml" "lagoon.persistent.name: &lagoon-nginx-name nginx-php"
  assert_file_contains "docker-compose.yml" "lagoon.persistent: &lagoon-drupal-files /app/docroot/sites/default/files/"
  assert_file_contains "docker-compose.yml" "lagoon.type: nginx-php-persistent"
  assert_file_contains "docker-compose.yml" "lagoon.name: *lagoon-nginx-name"
  assert_file_contains "docker-compose.yml" "lagoon.type: mariadb"
  assert_file_contains "docker-compose.yml" "lagoon.type: solr"
  assert_file_contains "docker-compose.yml" "lagoon.type: none"

  assert_file_contains ".env" "DREVOPS_LAGOON_ENABLE_DRUSH_ALIASES="

  popd >/dev/null || exit 1
}

assert_files_present_no_integration_lagoon() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"

  pushd "${dir}" >/dev/null || exit 1

  assert_file_not_exists ".lagoon.yml"
  assert_file_not_exists "drush/aliases.drushrc.php"
  assert_file_not_exists ".github/workflows/dispatch-webhook-lagoon.yml"
  assert_file_not_contains "docker-compose.yml" "labels"
  assert_file_not_contains "docker-compose.yml" "lagoon.type: cli-persistent"
  assert_file_not_contains "docker-compose.yml" "lagoon.persistent.name: &lagoon-nginx-name nginx-php"
  assert_file_not_contains "docker-compose.yml" "lagoon.persistent: &lagoon-drupal-files /app/docroot/sites/default/files/"
  assert_file_not_contains "docker-compose.yml" "lagoon.type: nginx-php-persistent"
  assert_file_not_contains "docker-compose.yml" "lagoon.name: *lagoon-nginx-name"
  assert_file_not_contains "docker-compose.yml" "lagoon.type: mariadb"
  assert_file_not_contains "docker-compose.yml" "lagoon.type: solr"
  assert_file_not_contains "docker-compose.yml" "lagoon.type: none"

  assert_file_not_contains ".env" "DREVOPS_DB_DOWNLOAD_LAGOON_ENVIRONMENT="
  assert_file_not_contains ".env" "DREVOPS_LAGOON_ENABLE_DRUSH_ALIASES="
  assert_file_not_contains "default.env.local" "DREVOPS_DB_DOWNLOAD_SSH_KEY_FILE="

  popd >/dev/null || exit 1
}

assert_files_present_integration_ftp() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"

  pushd "${dir}" >/dev/null || exit 1

  assert_file_contains ".env" "DREVOPS_DB_DOWNLOAD_FTP_HOST="
  assert_file_contains ".env" "DREVOPS_DB_DOWNLOAD_FTP_PORT="
  assert_file_contains ".env" "DREVOPS_DB_DOWNLOAD_FTP_FILE="
  assert_file_not_contains ".env" "DREVOPS_DB_DOWNLOAD_FTP_USER="
  assert_file_not_contains ".env" "DREVOPS_DB_DOWNLOAD_FTP_PASS="
  assert_file_contains "default.env.local" "DREVOPS_DB_DOWNLOAD_FTP_USER="
  assert_file_contains "default.env.local" "DREVOPS_DB_DOWNLOAD_FTP_PASS="

  popd >/dev/null || exit 1
}

assert_files_present_no_integration_ftp() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"

  pushd "${dir}" >/dev/null || exit 1

  assert_file_not_contains ".env" "DREVOPS_DB_DOWNLOAD_FTP_HOST="
  assert_file_not_contains ".env" "DREVOPS_DB_DOWNLOAD_FTP_PORT="
  assert_file_not_contains ".env" "DREVOPS_DB_DOWNLOAD_FTP_FILE="
  assert_file_not_contains ".env" "DREVOPS_DB_DOWNLOAD_FTP_USER="
  assert_file_not_contains ".env" "DREVOPS_DB_DOWNLOAD_FTP_PASS="
  assert_file_not_contains "default.env.local" "DREVOPS_DB_DOWNLOAD_FTP_USER="
  assert_file_not_contains "default.env.local" "DREVOPS_DB_DOWNLOAD_FTP_PASS="

  popd >/dev/null || exit 1
}

assert_files_present_integration_renovatebot() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"

  pushd "${dir}" >/dev/null || exit 1

  assert_file_exists "renovate.json"

  assert_file_contains ".circleci/config.yml" "renovatebot_self_hosted"
  assert_file_contains ".circleci/config.yml" "nightly_renovatebot_branch"
  assert_file_contains ".circleci/config.yml" "- *nightly_renovatebot_branch"

  assert_file_contains CI.md "Automated patching"

  popd >/dev/null || exit 1
}

assert_files_present_no_integration_renovatebot() {
  local dir="${1:-$(pwd)}"
  local suffix="${2:-star_wars}"

  pushd "${dir}" >/dev/null || exit 1

  assert_file_not_exists "renovate.json"

  assert_file_not_contains ".circleci/config.yml" "renovatebot_self_hosted"
  assert_file_not_contains ".circleci/config.yml" "nightly_renovatebot_branch"
  assert_file_not_contains ".circleci/config.yml" "- *nightly_renovatebot_branch"

  assert_file_not_contains CI.md "Automated patching"

  popd >/dev/null || exit 1
}

fixture_readme() {
  local dir="${1:-$(pwd)}"
  local name="${2:-Star Wars}"
  local org="${3:-Star Wars Org}"

  cat <<EOT >>"${dir}"/README.md
# ${name}
Drupal 9 implementation of ${name} for ${org}

[![CircleCI](https://circleci.com/gh/your_org/your_site.svg?style=shield)](https://circleci.com/gh/your_org/your_site)

[//]: # (DO NOT REMOVE THE BADGE BELOW. IT IS USED BY DREVOPS TO TRACK INTEGRATION)

[![DrevOps](https://img.shields.io/badge/DrevOps-DREVOPS_VERSION_URLENCODED-blue.svg)](https://github.com/drevops/drevops/tree/DREVOPS_VERSION)

some other text
EOT
}

fixture_composerjson() {
  local name="${1}"
  local machine_name="${2}"
  local org="${3}"
  local org_machine_name="${4}"
  local dir="${5:-$(pwd)}"

  cat <<EOT >>"${dir}"/composer.json
{
    "name": "${org_machine_name}/${machine_name}",
    "description": "Drupal 9 implementation of ${name} for ${org}"
}
EOT
}
################################################################################
#                               UTILITIES                                      #
################################################################################

# Run install script.
# shellcheck disable=SC2120
run_install_quiet() {
  pushd "${CURRENT_PROJECT_DIR}" >/dev/null || exit 1

  # Force install script to be downloaded from the local repo for testing.
  export DREVOPS_INSTALL_LOCAL_REPO="${LOCAL_REPO_DIR}"

  # Use unique temporary directory for each run.
  DREVOPS_INSTALL_TMP_DIR="${APP_TMP_DIR}/$(random_string)"
  prepare_fixture_dir "${DREVOPS_INSTALL_TMP_DIR}"
  export DREVOPS_INSTALL_TMP_DIR

  # Tests are using demo database and 'ahoy download-db' command, so we need
  # to set the CURL DB to test DB.
  #
  # Override demo database with test demo database. This is required to use
  # test assertions ("star wars") with demo database.
  #
  # Installer will load environment variable and it will take precedence over
  # the value in .env file.
  export DREVOPS_DB_DOWNLOAD_CURL_URL="$DREVOPS_INSTALL_DEMO_DB_TEST"

  # Enable the line below to show install debug information (for easy debug of
  # install script tests).
  # export DREVOPS_INSTALL_DEBUG=1

  # Enable the line below to show DrevOps debug information (for easy debug of tests).
  # export DREVOPS_DEBUG=1

  opt_quiet="--quiet"
  [ "${TEST_RUN_INSTALL_INTERACTIVE}" = "1" ] && opt_quiet=""

  run php "${CUR_DIR}/install.php" "${opt_quiet}" "$@"

  # Special treatment for cases where volumes are not mounted from the host.
  fix_host_dependencies "$@"

  popd >/dev/null || exit 1

  # shellcheck disable=SC2154
  echo "${output}"
}

# Run install in interactive mode.
#
# Use 'y' for yes and 'n' for 'no'.
#
# 'nothing' stands for user not providing an input and accepting suggested
# default values.
#
# @code
# answers=(
#   "Star wars" # name
#   "nothing" # machine_name
#   "nothing" # org
#   "nothing" # org_machine_name
#   "nothing" # module_prefix
#   "nothing" # profile
#   "nothing" # theme
#   "nothing" # URL
#   "nothing" # install_from_profile
#   "nothing" # download_db_source
#   "nothing" # database_store_type
#   "nothing" # deploy_type
#   "nothing" # preserve_ftp
#   "nothing" # preserve_acquia
#   "nothing" # preserve_lagoon
#   "nothing" # preserve_renovatebot
#   "nothing" # preserve_doc_comments
#   "nothing" # preserve_drevops_info
# )
# output=$(run_install_interactive "${answers[@]}")
# @endcode
run_install_interactive() {
  local answers=("${@}")
  local input

  for i in "${answers[@]}"; do
    val="${i}"
    [ "${i}" = "nothing" ] && val='\n' || val="${val}"'\n'
    input="${input}""${val}"
  done

  # Force installer to be interactive.
  export TEST_RUN_INSTALL_INTERACTIVE=1

  # Force TTY to get answers through pipe.
  export DREVOPS_INSTALLER_FORCE_TTY=1

  # shellcheck disable=SC2059,SC2119
  # ATTENTION! Questions change based on some answers, so using the same set of
  # answers for all tests will not work. Make sure that correct answers
  # provided for specific tests.
  printf "$input" | run_install_quiet
}

#
# Create a stub of installed dependencies.
#
# Used for fast unit testing of install functionality.
#
install_dependencies_stub() {
  local dir="${1:-$(pwd)}"

  pushd "${dir}" >/dev/null || exit 1

  mktouch "docroot/core/install.php"
  mktouch "docroot/modules/contrib/somemodule/somemodule.info.yml"
  mktouch "docroot/themes/contrib/sometheme/sometheme.info.yml"
  mktouch "docroot/profiles/contrib/someprofile/someprofile.info.yml"
  mktouch "docroot/sites/default/somesettingsfile.php"
  mktouch "docroot/sites/default/files/somepublicfile.php"
  mktouch "vendor/somevendor/somepackage/somepackage.php"
  mktouch "vendor/somevendor/somepackage/somepackage with spaces.php"
  mktouch "vendor/somevendor/somepackage/composer.json"
  mktouch "docroot/themes/custom/zzzsomecustomtheme/node_modules/somevendor/somepackage/somepackage.js"

  mktouch "docroot/modules/themes/custom/zzzsomecustomtheme/build/js/zzzsomecustomtheme.min.js"
  mktouch "tests/behat/screenshots/s1.jpg"
  mktouch ".data/db.sql"

  mktouch "docroot/sites/default/settings.local.php"
  mktouch "docroot/sites/default/services.local.yml"
  echo "version: \"2.3\"" >"docker-compose.override.yml"

  popd >/dev/null || exit 1
}

replace_core_stubs() {
  local dir="${1}"
  local token="${2}"

  replace_string_content "${token}" "some_other_site" "${dir}/docroot"
}

create_development_settings() {
  substep "Create development settings"
  assert_file_not_exists docroot/sites/default/settings.local.php
  assert_file_not_exists docroot/sites/default/services.local.yml
  assert_file_exists docroot/sites/default/default.settings.local.php
  assert_file_exists docroot/sites/default/default.services.local.yml
  cp docroot/sites/default/default.settings.local.php docroot/sites/default/settings.local.php
  cp docroot/sites/default/default.services.local.yml docroot/sites/default/services.local.yml
  assert_file_exists docroot/sites/default/settings.local.php
  assert_file_exists docroot/sites/default/services.local.yml
}

remove_development_settings() {
  substep "Remove development settings"
  rm -f docroot/sites/default/settings.local.php || true
  rm -f docroot/sites/default/services.local.yml || true
}

# Copy source code at the latest commit to the destination directory.
copy_code() {
  local dst="${1:-${BUILD_DIR}}"
  assert_dir_exists "${dst}"
  assert_git_repo "${CUR_DIR}"
  pushd "${CUR_DIR}" >/dev/null || exit 1
  # Copy latest commit to the build directory.
  git archive --format=tar HEAD | (cd "${dst}" && tar -xf -)
  popd >/dev/null || exit 1
}

# Prepare local repository from the current codebase.
prepare_local_repo() {
  local dir="${1:-$(pwd)}"
  local do_copy_code="${2:-1}"
  local commit

  if [ "${do_copy_code}" -eq 1 ]; then
    prepare_fixture_dir "${dir}"
    copy_code "${dir}"
  fi

  git_init 0 "${dir}"
  [ "$(git config --global user.name)" = "" ] && echo "==> Configuring global git user name." && git config --global user.name "Some User"
  [ "$(git config --global user.email)" = "" ] && echo "==> Configuring global git user email." && git config --global user.email "some.user@example.com"
  commit=$(git_add_all_commit "Initial commit" "${dir}")

  echo "${commit}"
}

prepare_global_gitconfig() {
  git config --global init.defaultBranch >/dev/null ||  git config --global init.defaultBranch "main"
}

prepare_global_gitignore() {
  filename="$HOME/.gitignore"
  filename_backup="${filename}".bak

  if git config --global --list | grep -q core.excludesfile; then
    git config --global core.excludesfile >/tmp/git_config_global_exclude
  fi

  [ -f "${filename}" ] && cp "${filename}" "${filename_backup}"

  cat <<EOT >"${filename}"
##
## Temporary files generated by various OSs and IDEs
##
Thumbs.db
._*
.DS_Store
.idea
.idea/*
*.sublime*
.project
.netbeans
.vscode
.vscode/*
nbproject
nbproject/*
EOT

  git config --global core.excludesfile "${filename}"
}

restore_global_gitignore() {
  filename=$HOME/.gitignore
  filename_backup="${filename}".bak
  [ -f "${filename_backup}" ] && cp "${filename_backup}" "${filename}"
  [ -f "/tmp/git_config_global_exclude" ] && git config --global core.excludesfile "$(cat /tmp/git_config_global_exclude)"
}

git_add() {
  local file="${1}"
  local dir="${2:-$(pwd)}"
  git --work-tree="${dir}" --git-dir="${dir}/.git" add "${dir}/${file}" >/dev/null
}

git_add_force() {
  local file="${1}"
  local dir="${2:-$(pwd)}"
  git --work-tree="${dir}" --git-dir="${dir}/.git" add -f "${dir}/${file}" >/dev/null
}

git_commit() {
  local message="${1}"
  local dir="${2:-$(pwd)}"

  assert_git_repo "${dir}"

  git --work-tree="${dir}" --git-dir="${dir}/.git" commit -m "${message}" >/dev/null
  commit=$(git --work-tree="${dir}" --git-dir="${dir}/.git" rev-parse HEAD)
  echo "${commit}"
}

git_add_all_commit() {
  local message="${1}"
  local dir="${2:-$(pwd)}"

  assert_git_repo "${dir}"

  git --work-tree="${dir}" --git-dir="${dir}/.git" add -A
  git --work-tree="${dir}" --git-dir="${dir}/.git" commit -m "${message}" >/dev/null
  commit=$(git --work-tree="${dir}" --git-dir="${dir}/.git" rev-parse HEAD)
  echo "${commit}"
}

git_init() {
  local allow_receive_update="${1:-0}"
  local dir="${2:-$(pwd)}"

  assert_not_git_repo "${dir}"
  git --work-tree="${dir}" --git-dir="${dir}/.git" init >/dev/null

  if [ "${allow_receive_update}" -eq 1 ]; then
    git --work-tree="${dir}" --git-dir="${dir}/.git" config receive.denyCurrentBranch updateInstead >/dev/null
  fi
}

# Replace string content in the directory.
replace_string_content() {
  local needle="${1}"
  local replacement="${2}"
  local dir="${3}"
  local sed_opts

  sed_opts=(-i) && [ "$(uname)" = "Darwin" ] && sed_opts=(-i '')

  set +e
  grep -rI \
    --exclude-dir=".git" \
    --exclude-dir=".idea" \
    --exclude-dir="vendor" \
    --exclude-dir="node_modules" \
    --exclude-dir=".data" \
    -l "${needle}" "${dir}" |
    xargs sed "${sed_opts[@]}" "s@$needle@$replacement@g" || true
  set -e
}

# Print step.
step() {
  debug ""
  # Using prefix different from command prefix in SUT for easy debug.
  debug "**> STEP: $1"
}

# Print sub-step.
substep() {
  debug ""
  debug "  > $1"
}

# Sync files to host in case if volumes are not mounted from host.
sync_to_host() {
  local dst="${1:-.}"
  # shellcheck disable=SC1090,SC1091
  [ -f "./.env" ] && t=$(mktemp) && export -p >"$t" && set -a && . "./.env" && set +a && . "$t" && rm "$t" && unset t
  [ "${DREVOPS_DEV_VOLUMES_MOUNTED}" = "1" ] && return
  docker cp -L "$(docker-compose ps -q cli)":/app/. "${dst}"
}

# Sync files to container in case if volumes are not mounted from host.
sync_to_container() {
  local src="${1:-.}"
  # shellcheck disable=SC1090,SC1091
  [ -f "./.env" ] && t=$(mktemp) && export -p >"$t" && set -a && . "./.env" && set +a && . "$t" && rm "$t" && unset t
  [ "${DREVOPS_DEV_VOLUMES_MOUNTED}" = "1" ] && return
  docker cp -L "${src}" "$(docker-compose ps -q cli)":/app/
}

# Special treatment for cases where volumes are not mounted from the host.
fix_host_dependencies() {
  # Replicate behaviour of install.php script to extract destination directory
  # passed as an argument.
  # shellcheck disable=SC2235
  ([ "${1}" = "--quiet" ] || [ "${1}" = "-q" ]) && shift
  # Destination directory, that can be overridden with the first argument to this script.
  DREVOPS_INSTALL_DST_DIR="${DREVOPS_INSTALL_DST_DIR:-$(pwd)}"
  DREVOPS_INSTALL_DST_DIR=${1:-${DREVOPS_INSTALL_DST_DIR}}

  pushd "${DREVOPS_INSTALL_DST_DIR}" >/dev/null || exit 1

  if [ -f docker-compose.yml ] && [ "${DREVOPS_DEV_VOLUMES_MOUNTED:-1}" != "1" ]; then
    sed -i -e "/###/d" docker-compose.yml
    assert_file_not_contains docker-compose.yml "###"
    sed -i -e "s/##//" docker-compose.yml
    assert_file_not_contains docker-compose.yml "##"
  fi

  popd >/dev/null || exit 1
}
