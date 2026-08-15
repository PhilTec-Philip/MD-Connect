//
//  This file is derived from the FiveNet protobuf definitions.
//  https://github.com/fivenet-app/fivenet
//
//  Copyright 2023 Alexander Trost (FiveNet)
//  Modifications Copyright 2026 Philip Müller (FiveNet Mobile)
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import SwiftProtobuf

extension Resources_Accounts_Character: Identifiable {
    public var id: Int64 { Int64(char.userID) }
}

extension Resources_Users_User: Identifiable {
    public var id: Int32 { userID }
}

extension Resources_Users_Short_UserShort: Identifiable {
    public var id: Int32 { userID }
}

extension Resources_Centrum_Dispatches_Dispatch: Identifiable {}
extension Resources_Centrum_Units_Unit: Identifiable {}

extension Resources_Livemap_Markers_UserMarker: Identifiable {
    public var id: Int32 { userID }
}

extension Resources_Livemap_Markers_MarkerMarker: Identifiable {}

extension Resources_Wiki_PageShort: Identifiable {}

extension Resources_Documents_DocumentShort: Identifiable {}
extension Resources_Documents_Document: Identifiable {}
extension Resources_Documents_Category_Category: Identifiable {}
extension Resources_Documents_Templates_TemplateShort: Identifiable {}
extension Resources_Documents_Comment_Comment: Identifiable {}
extension Resources_Documents_Relations_DocumentRelation: Identifiable {}
extension Resources_Documents_References_DocumentReference: Identifiable {}
extension Resources_Documents_Requests_DocRequest: Identifiable {}
extension Resources_Documents_Approval_ApprovalTask: Identifiable {}

extension Resources_Jobs_Colleagues_Colleague: Identifiable {
    public var id: Int32 { userID }
}

extension Resources_Jobs_Colleagues_Activity_ColleagueActivity: Identifiable {}
extension Resources_Jobs_Labels_Label: Identifiable {}
extension Resources_Jobs_Timeclock_TimeclockEntry: Identifiable {
    public var id: String {
        let date = hasDate ? date.timestamp.seconds : 0
        let start = hasStartTime ? startTime.timestamp.seconds : 0
        return "\(userID)-\(job)-\(date)-\(start)"
    }
}
extension Resources_Jobs_Conduct_ConductEntry: Identifiable {}

extension Resources_Qualifications_Qualification: Identifiable {}
extension Resources_Qualifications_QualificationShort: Identifiable {}
extension Resources_Qualifications_QualificationRequirement: Identifiable {}
extension Resources_Qualifications_QualificationResult: Identifiable {}
extension Resources_Qualifications_QualificationRequest: Identifiable {
    public var id: String { "\(qualificationID)-\(userID)" }
}

extension Resources_Mailer_Emails_Email: Identifiable {}
extension Resources_Mailer_Threads_Thread: Identifiable {}
extension Resources_Mailer_Messages_Message: Identifiable {}
extension Resources_Mailer_Threads_ThreadState: Identifiable {
    public var id: String { "\(threadID)-\(emailID)" }
}

extension Resources_Permissions_Permissions_Role: Identifiable {}
extension Resources_Permissions_Attributes_RoleAttribute: Identifiable {
    public var id: Int64 { attrID }
}
extension Resources_Audit_AuditEntry: Identifiable {}
extension Resources_Discord_Channel: Identifiable {}
extension Resources_Discord_Guild: Identifiable {}
extension Resources_Laws_LawBook: Identifiable {}
extension Resources_Laws_Law: Identifiable {}
extension Resources_Cron_Cronjob: Identifiable {
    public var id: String { name }
}
extension Resources_Accounts_Account: Identifiable {}
extension Resources_File_File: Identifiable {}
