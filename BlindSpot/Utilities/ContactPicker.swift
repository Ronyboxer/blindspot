//
//  ContactPicker.swift
//  Blind Spot
//
//  Wraps the system contact picker (CNContactPickerViewController) so the rider
//  can choose an emergency contact instead of typing a name + number. The picker
//  runs out-of-process, so it needs NO Contacts permission.
//
//  Selecting a specific phone number returns that contact's name + number.
//

import SwiftUI
import ContactsUI
import Contacts

struct ContactPicker: UIViewControllerRepresentable {
    /// Called with (full name, phone number) when the user picks a number.
    var onPick: (String, String) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        // Show only phone numbers; tapping one selects it directly.
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForSelectionOfProperty = NSPredicate(format: "key == 'phoneNumbers'")
        return picker
    }

    func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (String, String) -> Void
        init(onPick: @escaping (String, String) -> Void) { self.onPick = onPick }

        // User tapped a specific phone number.
        func contactPicker(_ picker: CNContactPickerViewController,
                           didSelect contactProperty: CNContactProperty) {
            let name = CNContactFormatter.string(from: contactProperty.contact, style: .fullName) ?? ""
            let phone = (contactProperty.value as? CNPhoneNumber)?.stringValue ?? ""
            onPick(name, phone)
        }

        // User tapped a whole contact (fallback): use the first phone number.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
            onPick(name, phone)
        }
    }
}
