<?php

namespace Drupal\adsk_installer\Form;

use Drupal\Core\Form\FormStateInterface;

/**
 * Provides a form to choose the site template and optional add-on recipes.
 *
 * @todo Present this as a mini project browser once
 *   https://www.drupal.org/i/3450629 is fixed.
 */
final class RecipesStarterkitForm extends InstallerFormBase {

  /**
   * {@inheritdoc}
   */
  public function getFormId(): string {
    return 'adsk_installer_recipes_form';
  }

  /**
   * {@inheritdoc}
   */
  public function buildForm(array $form, FormStateInterface $form_state): array {
    $form['#title'] = $this->t('Select Starter Kit');

    $form['help'] = [
      '#prefix' => '<p class="cms-installer__subhead">',
      '#markup' => $this->t('You can change your mind later.'),
      '#suffix' => '</p>',
    ];

    $options = [
      'adsk_community' => $this->t('Community'),
      'adsk_headless' => $this->t('Headless'),
      'adsk_low_code' => $this->t('Low-Code'),
    ];

    $form['add_ons'] = [
      '#prefix' => '<div class="cms-installer__form-group">',
      '#suffix' => '</div>',
      '#type' => 'radios',
      '#required' => TRUE,
      '#options' => $options,
//      '#default_value' => 'adsk_community',
    ];

    $form['actions'] = [
      'submit' => [
        '#type' => 'submit',
        '#value' => $this->t('Next'),
        '#button_type' => 'primary',
      ],
      '#type' => 'actions',
      '#states' => [
//        'disabled' => [
//          ':input[name="add_ons"]' => [
//            'checked' => FALSE,
//          ]
//        ],
        // Action to take.
        'enabled' => [
          ':input[name="add_ons"]' => [
            'checked' => TRUE,
          ]
        ]
      ]
    ];
    return parent::buildForm($form, $form_state);
  }

  /**
   * {@inheritdoc}
   */
  public function submitForm(array &$form, FormStateInterface $form_state): void {
    global $install_state;
    $pressed_button = $form_state->getTriggeringElement();
    // Only choose add-ons if the Next button was pressed.
    if ($pressed_button && end($pressed_button['#array_parents']) === 'submit') {
      $add_ons = $form_state->getValue('add_ons');
      if ($add_ons) {
        $install_state['parameters']['recipes'][] = $add_ons;
      }
      else {
        $install_state['parameters']['recipes'] = ['adsk_community'];
      }
    }
  }

}
