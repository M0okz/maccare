import SwiftUI

struct ApplicationPermissionAppearance {
    let symbol: String
    let color: Color
    let detail: String

    init(service: String) {
        switch service {
        case "kTCCServiceAccessibility":
            symbol = "accessibility"; color = .blue
            detail = "Applications autorisées à interagir avec votre Mac et à le contrôler."
        case "kTCCServiceSystemPolicyAllFiles":
            symbol = "internaldrive.fill"; color = .purple
            detail = "Applications pouvant accéder aux fichiers protégés de votre Mac."
        case "kTCCServiceScreenCapture":
            symbol = "record.circle"; color = .pink
            detail = "Applications autorisées à enregistrer ou partager le contenu de vos écrans."
        case "kTCCServiceListenEvent":
            symbol = "keyboard.fill"; color = .orange
            detail = "Applications pouvant observer les entrées du clavier, de la souris ou du trackpad."
        case "kTCCServiceCamera":
            symbol = "camera.fill"; color = .pink; detail = "Applications ayant demandé à utiliser votre caméra."
        case "kTCCServiceMicrophone":
            symbol = "mic.fill"; color = .orange; detail = "Applications ayant demandé à utiliser votre microphone."
        case "kTCCServiceAppleEvents":
            symbol = "gearshape.2.fill"; color = .indigo; detail = "Applications pouvant envoyer des commandes à d’autres applications."
        case "kTCCServiceDeveloperTool":
            symbol = "hammer.fill"; color = .orange; detail = "Outils autorisés à exécuter des logiciels pour le développement."
        case "kTCCServicePhotos":
            symbol = "photo.on.rectangle.angled"; color = .pink; detail = "Applications ayant demandé à accéder à votre photothèque."
        case "kTCCServiceAddressBook":
            symbol = "person.crop.rectangle.fill"; color = .brown; detail = "Applications ayant demandé à consulter vos contacts."
        default:
            symbol = service.isEmpty ? "lock.shield.fill" : "folder.fill"
            color = .purple
            detail = service.isEmpty ? "Retrouvez les accès accordés à vos applications, regroupés par fonctionnalité." : "Examinez les applications et gérez leurs accès à cette fonctionnalité."
        }
    }
}
