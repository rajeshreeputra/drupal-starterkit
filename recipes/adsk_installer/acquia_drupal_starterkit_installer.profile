<?php

declare(strict_types=1);

use Drupal\Component\Utility\Random;
use Drupal\Core\Extension\ModuleInstallerInterface;
use Drupal\Core\File\FileUrlGeneratorInterface;
use Drupal\Core\Installer\Form\SiteConfigureForm;
use Drupal\Core\Installer\Form\SiteSettingsForm;
use Drupal\Core\Recipe\Recipe;
use Drupal\Core\Recipe\RecipeRunner;
use Drupal\adsk_installer\Form\RecipesStarterkitForm;
use Drupal\adsk_installer\Form\RecipesAddOnForm;
use Drupal\adsk_installer\Form\SiteNameForm;
use Symfony\Component\Yaml\Yaml;

/**
 * Implements hook_install_tasks().
 */
function adsk_installer_install_tasks(): array {
  // Ensure our forms are loadable in all situations, even if the installer is
  // not a Composer-managed package.
  \Drupal::service('class_loader')
    ->addPsr4('Drupal\\adsk_installer\\', __DIR__ . '/src');

  return [
    'adsk_installer_uninstall_myself' => [
      // As a final task, this profile should uninstall itself.
    ],
  ];
}

/**
 * Implements hook_install_tasks_alter().
 */
function adsk_installer_install_tasks_alter(array &$tasks, array $install_state): void {
  $insert_before = function (string $key, array $additions) use (&$tasks): void {
    $key = array_search($key, array_keys($tasks), TRUE);
    if ($key === FALSE) {
      return;
    }
    // This isn't very clean, but it's the only way to positionally splice into
    // an associative (and therefore by definition unordered) array.
    $tasks_before = array_slice($tasks, 0, $key, TRUE);
    $tasks_after = array_slice($tasks, $key, NULL, TRUE);
    $tasks = $tasks_before + $additions + $tasks_after;
  };

  $insert_before('install_settings_form', [
    'adsk_installer_choose_recipes' => [
      'display_name' => t('Choose add-ons'),
      'type' => 'form',
      'run' => array_key_exists('recipes', $install_state['parameters']) ? INSTALL_TASK_SKIP : INSTALL_TASK_RUN_IF_REACHED,
      'function' => RecipesStarterkitForm::class,
    ],
    'adsk_installer_addons' => [
      'display_name' => t('Extend Acquia Drupal Starter Kit with Add-ons'),
      'type' => 'form',
      'run' => array_key_exists('recipes_starterkit_addons', $install_state['parameters']) ? INSTALL_TASK_SKIP : INSTALL_TASK_RUN_IF_REACHED,
      'function' => RecipesAddOnForm::class,
    ],
    'adsk_installer_site_name_form' => [
      'display_name' => t('Name your site'),
      'type' => 'form',
      'run' => array_key_exists('site_name', $install_state['parameters']) ? INSTALL_TASK_SKIP : INSTALL_TASK_RUN_IF_REACHED,
      'function' => SiteNameForm::class,
    ],
  ]);

  // Set English as the default language; it can be changed mid-stream. We can't
  // use the passed-in $install_state because it's not passed by reference.
  $GLOBALS['install_state']['parameters'] += ['langcode' => 'en'];

  // The database settings form should be submitted programmatically in the
  // trial experience.
  $tasks['install_settings_form']['function'] = 'adsk_installer_database_settings';
  unset($tasks['install_settings_form']['type']);

  // Submit the site configuration form programmatically.
  $tasks['install_configure_form'] = [
    'function' => 'adsk_installer_configure_site',
  ];

  // Wrap the install_profile_modules() function, which returns a batch job, and
  // add all the necessary operations to apply the chosen template recipe.
  $tasks['install_profile_modules']['function'] = 'adsk_installer_apply_recipes';

  // Since we're using recipes, we can skip `install_profile_themes` and
  // `install_install_profile`.
  $tasks['install_profile_themes']['run'] = INSTALL_TASK_SKIP;
  $tasks['install_install_profile']['run'] = INSTALL_TASK_SKIP;
}

/**
 * Implements hook_form_alter() for install_settings_form.
 *
 * @see \Drupal\Core\Installer\Form\SiteSettingsForm
 */
function adsk_installer_form_install_settings_form_alter(array &$form): void {
  // Default to SQLite, if available, because it doesn't require any additional
  // configuration.
  $sqlite = 'Drupal\sqlite\Driver\Database\sqlite';
  if (array_key_exists($sqlite, $form['driver']['#options']) && extension_loaded('pdo_sqlite')) {
    $form['driver']['#default_value'] = $sqlite;
  }
}

/**
 * Runs a batch job that applies the template and add-on recipes.
 *
 * @param array $install_state
 *   An array of information about the current installation state.
 *
 * @return array
 *   The batch job definition.
 */
function adsk_installer_apply_recipes(array &$install_state): array {
  $batch = install_profile_modules($install_state);
  $batch['title'] = t('Setting up your site');

  $cookbook_path = \Drupal::root() . '/recipes';

  foreach ($install_state['parameters']['recipes'] as $recipe) {
    $recipe = Recipe::createFromDirectory($cookbook_path . '/' . $recipe);

    foreach (RecipeRunner::toBatchOperations($recipe) as $operation) {
      $batch['operations'][] = $operation;
    }
  }
  return $batch;
}

/**
 * Programmatically submits the database settings form if needed.
 */
function adsk_installer_database_settings(array &$install_state): ?array {
  $interactive = $install_state['interactive'];
  $result = install_get_form(SiteSettingsForm::class, $install_state);
  $install_state['interactive'] = $interactive;

  return $result;
}

/**
 * Programmatically executes core's site configuration form.
 */
function adsk_installer_configure_site(array &$install_state): ?array {
  $random_password = (new Random())->machineName();
  $host = \Drupal::request()->getHost();

  $install_state['forms'] += [
    'install_configure_form' => [
      'site_name' => $install_state['parameters']['site_name'],
      'site_mail' => "no-reply@$host",
      'account' => [
        'name' => 'admin',
        'mail' => "admin@$host",
        'pass' => [
          'pass1' => $random_password,
          'pass2' => $random_password,
        ],
      ],
    ],
  ];
  // Temporarily switch to non-interactive mode and programmatically submit
  // the form.
  $interactive = $install_state['interactive'];
  $install_state['interactive'] = FALSE;
  $result = install_get_form(SiteConfigureForm::class, $install_state);
  $install_state['interactive'] = $interactive;

  $messenger = \Drupal::messenger();
  // Clear all previous status messages to avoid clutter.
  $messenger->deleteByType($messenger::TYPE_STATUS);

  $message = t('Make a note of your login details to access your site later:<br />Username: admin<br />Password: @password', [
    '@password' => $install_state['forms']['install_configure_form']['account']['pass']['pass1'],
  ]);
  $messenger->addStatus($message);

  return $result;
}

/**
 * Implements hook_library_info_alter().
 */
function adsk_installer_library_info_alter(array &$libraries, string $extension): void {
  global $install_state;
  // If a library file's path starts with `/`, the library collection system
  // treats it as relative to the base path.
  // @see \Drupal\Core\Asset\LibraryDiscoveryParser::buildByExtension()
  $base_path = '/' . $install_state['profiles']['adsk_installer']->getPath();

  if ($extension === 'claro') {
    $libraries['maintenance-page']['css']['theme']["$base_path/css/gin-variables.css"] = [];
    $libraries['maintenance-page']['css']['theme']["$base_path/css/fonts.css"] = [];
    $libraries['maintenance-page']['css']['theme']["$base_path/css/installer-styles.css"] = [];
    $libraries['maintenance-page']['css']['theme']["$base_path/css/add-ons.css"] = [];
    $libraries['maintenance-page']['css']['theme']["$base_path/css/language-dropdown.css"] = [];
    $libraries['maintenance-page']['js']["$base_path/js/language-dropdown.js"] = [];
    $libraries['maintenance-page']['dependencies'][] = 'core/once';
  }
  if ($extension === 'core') {
    $libraries['drupal.progress']['js']["$base_path/js/progress.js"] = [];
  }
}

/**
 * Uninstalls this install profile, as a final step.
 *
 * @see drupal_install_system()
 */
function adsk_installer_uninstall_myself(): void {
  // `drupal_install_system()` sets `profile` in `core.extension` regardless
  // of whether the profile is actually installed by the module installer.
  \Drupal::configFactory()
    ->getEditable('core.extension')
    ->clear('profile')
    ->save();
}

/**
 * Implements hook_theme_registry_alter().
 */
function adsk_installer_theme_registry_alter(array &$hooks): void {
  global $install_state;
  $installer_path = $install_state['profiles']['adsk_installer']->getPath();

  $hooks['install_page']['path'] = $installer_path . '/templates';
}

/**
 * Preprocess function for all pages in the installer.
 */
function adsk_installer_preprocess_install_page(array &$variables): void {
  // Don't show the task list or the version of Drupal.
  unset($variables['page']['sidebar_first'], $variables['site_version']);

  global $install_state;
  $images_path = $install_state['profiles']['adsk_installer']->getPath() . '/images';
  $images_path = \Drupal::service(FileUrlGeneratorInterface::class)
    ->generateString($images_path);
  $variables['images_path'] = $images_path;
}
