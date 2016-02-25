//
//  Email.swift
//  Swift Mailing List
//
//  Created by Matthew Palmer on 4/02/2016.
//  Copyright © 2016 Matthew Palmer. All rights reserved.
//

import UIKit
import RealmSwift
import Freddy

/// An email as a Realm object. The difference between `Email` and `NetworkEmail` is that `NetworkEmail` is much more inert--it does not exist in a Realm.
final class Email: Object {
    dynamic var id: String = ""
    dynamic var from: String = ""
    dynamic var mailingList: String = ""
    dynamic var content: String = ""
    dynamic var archiveURL: String?
    dynamic var date: NSDate = NSDate(timeIntervalSince1970: 1)
    dynamic var subject: String = ""
    dynamic var inReplyTo: Email?
    let references: List<Email> = List<Email>()
    let descendants: List<Email> = List<Email>()
    
    override static func primaryKey() -> String? {
        return "id"
    }
    
    var isComplete: Bool {
        // A 'complete' email is able to be used in the app and does not require retrieval from the backend.
        // Check a small subset of the properties necessary.
        return id.characters.count > 0
            && from.characters.count > 0
            && mailingList.characters.count > 0
            && content.characters.count > 0
            && subject.characters.count > 0
    }
}

extension Email: Equatable {}

func ==(lhs: Email, rhs: Email) -> Bool {
    return lhs.id == rhs.id
}

extension Email: Hashable {
    override var hashValue: Int { return id.hashValue }
}

enum EmailError: ErrorType {
    case InvalidDate
}

extension Email {
    class func createFromNetworkEmail(networkEmail: NetworkEmail, inRealm realm: Realm) throws -> Email {
        let email = Email()
        email.id = networkEmail.id
        email.from = networkEmail.from
        email.date = networkEmail.date
        email.subject = networkEmail.subject
        email.mailingList = networkEmail.mailingList
        email.content = networkEmail.content
        email.archiveURL = networkEmail.archiveURL
        
        func emailsToCreate(fromListOfIds ids: [String], inRealm realm: Realm) -> [Email] {
            let predicate = NSPredicate(format: "id IN %@", ids)
            let emailsInDatabase = Set<Email>(realm.objects(Email)
                .filter(predicate))
                .map { $0.id } + [networkEmail.id] // In case of self-references
            
            let emailsNotInDatabase = Set<String>(ids).subtract(emailsInDatabase)
            
            let emailsToCreate: Array<Email> = (emailsNotInDatabase).map { id in
                let email = Email()
                email.id = id
                return email
            }
            
            return emailsToCreate
        }
        
        let descendantIDs = networkEmail.descendants
        let descendantsToCreate = emailsToCreate(fromListOfIds: descendantIDs, inRealm: realm)
        
        let referenceIDs = networkEmail.references
        let referencesToCreate = emailsToCreate(fromListOfIds: referenceIDs, inRealm: realm)
        
        let inReplyTo = networkEmail.inReplyTo
        let inReplyToToCreate: [Email]
        if let inReplyTo = inReplyTo {
            inReplyToToCreate = emailsToCreate(fromListOfIds: [inReplyTo], inRealm: realm)
        } else {
            inReplyToToCreate = []
        }
        
        try realm.write {
            realm.add(email, update: true)
            realm.add(descendantsToCreate)
            realm.add(referencesToCreate)
            realm.add(inReplyToToCreate)
            
            func addEmailsWithIds(ids: [String], toList list: List<Email>) {
                let toAdd = realm.objects(Email).filter("id in %@", ids)
                list.appendContentsOf(toAdd)
            }
            
            addEmailsWithIds(descendantIDs, toList: email.descendants)
            addEmailsWithIds(referenceIDs, toList: email.references)
            
            if let inReplyTo = inReplyTo {
                email.inReplyTo = realm.objects(Email).filter("id == %@", inReplyTo).first
            }
        }

        return email
    }
    
    class func createFromJSON(json: JSON, inRealm realm: Realm) throws -> Email {
        return try Email.createFromNetworkEmail(try NetworkEmail.createFromJSON(json), inRealm: realm)
    }
    
    class func createFromJSONData(jsonData: NSData, realm: Realm) throws -> Email {
        let json = try JSON(data: jsonData)
        return try Email.createFromJSON(json, inRealm: realm)
    }
}