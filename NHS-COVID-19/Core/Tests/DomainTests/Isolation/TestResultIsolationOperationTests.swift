//
// Copyright © 2021 DHSC. All rights reserved.
//

import Combine
import Common
import Scenarios
import TestSupport
import XCTest
@testable import Domain

class TestResultIsolationOperationTests: XCTestCase {
    struct Instance: TestProp {
        struct Configuration: TestPropConfiguration {
            var today = LocalDay.today
            lazy var selfDiagnosisDay = today.gregorianDay
            var encryptedStore = MockEncryptedStore()
            var isolationInfo = IsolationInfo(indexCaseInfo: nil, contactCaseInfo: nil)
            var isolationConfiguration = IsolationConfiguration(
                maxIsolation: 16,
                contactCase: 11,
                indexCaseSinceSelfDiagnosisOnset: 6,
                indexCaseSinceSelfDiagnosisUnknownOnset: 4,
                housekeepingDeletionPeriod: 14,
                indexCaseSinceNPEXDayNoSelfDiagnosis: 6,
                testResultPollingTokenRetentionPeriod: 28
            )

            public init() {}
        }

        let store: IsolationInfo
        let isolationState: IsolationLogicalState
        let isolationConfiguration: IsolationConfiguration
        let currentDateProvider: DateProviding

        init(configuration: Configuration) {
            store = configuration.isolationInfo
            isolationState = IsolationLogicalState(
                today: configuration.today,
                info: configuration.isolationInfo,
                configuration: configuration.isolationConfiguration
            )
            isolationConfiguration = configuration.isolationConfiguration
            currentDateProvider = MockDateProvider(getDate: { configuration.today.startOfDay })
        }
    }

    @Propped
    var instance: Instance

    var store: IsolationInfo {
        instance.store
    }

    var isolationState: IsolationLogicalState {
        instance.isolationState
    }

    var configuration: IsolationConfiguration {
        instance.isolationConfiguration
    }

    var currentDateProvider: DateProviding {
        instance.currentDateProvider
    }

    func testPositiveTestShouldUpdateWhileBeingInSymptomaticIsolation() throws {
        $instance.isolationInfo.indexCaseInfo = IndexCaseInfo(selfDiagnosisDay: $instance.selfDiagnosisDay, onsetDay: nil, testResult: nil)

        let selfDiagnosisDay = LocalDay.today.advanced(by: -2).gregorianDay
        let testReceivedDay = LocalDay.today.gregorianDay

        // Given
        let isolationInfo = IsolationInfo(indexCaseInfo: IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: nil),
            testInfo: nil
        ), contactCaseInfo: nil)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: testReceivedDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .update)
    }

    func testPositiveRequiresConfirmatoryTestShouldNotBeSavedWhileBeingInSymptomaticIsolation() throws {
        $instance.isolationInfo.indexCaseInfo = IndexCaseInfo(selfDiagnosisDay: $instance.selfDiagnosisDay, onsetDay: nil, testResult: nil)

        let selfDiagnosisDay = LocalDay.today.advanced(by: -2).gregorianDay
        let testReceivedDay = LocalDay.today.gregorianDay

        // Given
        let isolationInfo = IsolationInfo(indexCaseInfo: IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: nil),
            testInfo: nil
        ), contactCaseInfo: nil)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: testReceivedDay.advanced(by: -1).startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .nothing)
    }

    func testInIsolationEnteringNewPositiveRequiresConfirmatoryTestShouldNotOverrideExistingOne() {
        let firstRapidTestReceivedDay = LocalDay.today.advanced(by: -3).gregorianDay
        let firstRapidTestNpexDay = firstRapidTestReceivedDay.advanced(by: -1)

        let secondRapidTestReceivedDay = LocalDay.today

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: true,
                receivedOnDay: firstRapidTestReceivedDay,
                testEndDay: firstRapidTestNpexDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: secondRapidTestReceivedDay.advanced(by: -1).startOfDay,
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .nothing)
    }

    func testInIsolationEnteringNewPositiveTestShouldUpdateExistingOne() {
        let firstRapidTestReceivedDay = LocalDay.today.advanced(by: -4).gregorianDay
        let firstRapidTestNpexDay = firstRapidTestReceivedDay.advanced(by: -1)

        let secondRapidTestReceivedDay = LocalDay.today.gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: true,
                receivedOnDay: firstRapidTestReceivedDay,
                testEndDay: firstRapidTestNpexDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: secondRapidTestReceivedDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .update)
    }

    func testInIsolationEnteringNewPositiveTestShouldNotOverrideExistingOne() {
        let firstRapidTestReceivedDay = LocalDay.today.gregorianDay.advanced(by: -1)
        let firstRapidTestNpexDay = firstRapidTestReceivedDay.advanced(by: -1)

        let secondRapidTestReceivedDay = LocalDay.today.gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: firstRapidTestReceivedDay,
                testEndDay: firstRapidTestNpexDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: secondRapidTestReceivedDay.advanced(by: -1).startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .nothing)
    }

    func testShouldStartIsolationBecauseOfPositiveTestResultRequiresConfirmatoryTestAfterBeingRecentlyReleasedFromIsolation() {
        let npexDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceNPEXDayNoSelfDiagnosis.days - 1).gregorianDay
        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: .init(result: .positive,
                            testKitType: .rapidResult,
                            requiresConfirmatoryTest: true,
                            shouldOfferFollowUpTest: true,
                            receivedOnDay: npexDay,
                            testEndDay: npexDay)
        )
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: LocalDay.today.startOfDay,
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwrite)
    }

    func testShouldStartIsolationBecauseOfPositiveTestResultRequiresConfirmatoryTestAfterBeingRecentlyReleasedFromContactIsolation() {
        let exposureDay = LocalDay.today.advanced(by: -15).gregorianDay
        let isolationFromStartOfDay = LocalDay.today.advanced(by: -15).gregorianDay
        let contactCaseInfo = ContactCaseInfo(
            exposureDay: exposureDay,
            isolationFromStartOfDay: isolationFromStartOfDay
        )
        let isolationInfo = IsolationInfo(indexCaseInfo: nil, contactCaseInfo: contactCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: LocalDay.today.startOfDay,
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwrite)
    }

    func testNotOverwritePositiveTestResult() throws {
        let testDay = GregorianDay(year: 2020, month: 7, day: 13)
        let testEndDay = GregorianDay(year: 2020, month: 7, day: 16)

        let isolationInfo = IsolationInfo(indexCaseInfo: IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        ), contactCaseInfo: nil)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .negative,
                testKitType: .labResult,
                endDate: LocalDay.today.startOfDay,
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .nothing)
    }

    func testDoNothingWhenVoidResult() throws {
        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: IsolationInfo(),
            result: VirologyStateTestResult(
                testResult: .void,
                testKitType: .labResult,
                endDate: LocalDay.today.startOfDay,
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .nothing)
    }

    func testNewTestResultShouldBeSavedWhenNewTestResultIsPositiveAndPreviousTestResultIsNegative() throws {
        let testReceivedDay = GregorianDay(year: 2020, month: 7, day: 16)

        // Given
        let isolationInfo = IsolationInfo(indexCaseInfo: IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: testReceivedDay.advanced(by: -2), onsetDay: nil),
            testInfo: IndexCaseInfo.TestInfo(result: .negative, testKitType: .labResult, requiresConfirmatoryTest: false, shouldOfferFollowUpTest: false, receivedOnDay: testReceivedDay.advanced(by: -1), testEndDay: nil)
        ), contactCaseInfo: nil)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: LocalDay.today.startOfDay,
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwrite)
    }

    func testNewTestResultShouldBeSavedWhenNewTestResultIsPositiveAndPreviousTestResultIsNil() throws {
        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: IsolationInfo(),
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: LocalDay.today.startOfDay,
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwrite)
    }

    func testNewTestResultShouldBeIgnoredWhenNewTestResultIsNegativeAndPreviousTestResultIsNegative() throws {
        let testDay = LocalDay.today.gregorianDay.advanced(by: -1)

        // Given
        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .negative,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay.advanced(by: -4),
                testEndDay: testDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .negative,
                testKitType: .labResult,
                endDate: LocalDay.today.startOfDay,
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .nothing)
    }

    func testNewTestResultShouldBeSavedWhenNewTestResultIsNegativeAndPreviousTestResultIsNil() throws {
        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: IsolationInfo(),
            result: VirologyStateTestResult(
                testResult: .negative,
                testKitType: .labResult,
                endDate: LocalDay.today.startOfDay,
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwrite)
    }

    func testNewTestNegativeResultShouldOverwriteWhenUnconfirmedEndDateIsOlder() throws {
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = testDay.advanced(by: -6)
        let newEndDay = LocalDay.today.gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .negative,
                testKitType: .labResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .update)
    }

    func testNewTestNegativeResultShouldDoNothingWhenUnconfirmedEndDateIsNewer() throws {
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = testDay.advanced(by: -6)
        let newEndDay = testDay.advanced(by: -7)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .negative,
                testKitType: .labResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .nothing)
    }

    func testNewTestNegativeResultShouldUpdateWhenAssumedOnsetDateIsOlder() throws {
        let selfDiagnosisDay = LocalDay.today.gregorianDay.advanced(by: -6)
        let endDay = LocalDay.today

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: nil),
            testInfo: nil
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .negative,
                testKitType: .labResult,
                endDate: endDay.startOfDay,
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .update)
    }

    func testNewTestNegativeResultShouldDoNothingWhenAssumedOnsetDateIsNewer() throws {
        let selfDiagnosisDay = LocalDay.today.gregorianDay.advanced(by: -3)
        let endDay = LocalDay.today.gregorianDay.advanced(by: -7)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: nil),
            testInfo: nil
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .negative,
                testKitType: .labResult,
                endDate: endDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .nothing)
    }

    func testNewPositiveResultIgnoredIfThereIsCurrentIsolationAndResultIsOlder() {
        let exposureDay = LocalDay.today.advanced(by: -10).gregorianDay
        let isolationFromStartOfDay = LocalDay.today.advanced(by: -10).gregorianDay
        let contactCaseInfo = ContactCaseInfo(
            exposureDay: exposureDay,
            isolationFromStartOfDay: isolationFromStartOfDay
        )
        let isolationInfo = IsolationInfo(indexCaseInfo: nil, contactCaseInfo: contactCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: LocalDay.today.advanced(by: -21).startOfDay,
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .ignore)
    }

    func testNewPositiveResultOverwriteIfSelfDiagnosisOnsetDayIsNewerThanTest() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay
        let endDay = LocalDay.today.gregorianDay.advanced(by: -1)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: nil
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: endDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .update)
    }

    func testNewPositiveResultUpdatePositiveIfSelfDiagnosisOnsetDayIsNewerThanTheTest() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay
        let testDay = LocalDay.today.gregorianDay
        let endDay = LocalDay.today.gregorianDay.advanced(by: -1)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: true,
                receivedOnDay: testDay,
                testEndDay: nil
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: endDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .update)
    }

    func testNewPositiveResultUpdateAndConfirmPositiveIfSelfDiagnosisOnsetDayIsNewerThanTheTest() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay
        let testDay = LocalDay.today.gregorianDay
        let endDay = LocalDay.today.gregorianDay.advanced(by: -1)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: nil
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: endDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .updateAndConfirm)
    }

    func testNewPositiveResultOverwriteIfManualTestEntryDayIsNewerThanTheTest() {
        let npexDay = LocalDay.today.gregorianDay
        let testDay = LocalDay.today.gregorianDay
        let endDay = LocalDay.today.gregorianDay.advanced(by: -1)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: true,
                receivedOnDay: testDay,
                testEndDay: npexDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: endDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwrite)
    }

    func testNewPositiveResultOverwriteAndConfirmedIfManualTestEntryDayIsNewerThanTheTest() {
        let npexDay = LocalDay.today.gregorianDay
        let testDay = LocalDay.today.gregorianDay
        let endDay = LocalDay.today.gregorianDay.advanced(by: -1)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: npexDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: endDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwrite)
    }

    func testNewPositiveResultOverwriteIfSelfDiagnosisDayIsNewerThanTheTest() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay
        let testDay = LocalDay.today.gregorianDay
        let endDay = LocalDay.today.gregorianDay.advanced(by: -1)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: nil),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: true,
                receivedOnDay: testDay,
                testEndDay: nil
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: endDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .update)
    }

    func testNewPositiveResultOverwriteAndConfirmedIfSelfDiagnosisDayIsNewerThanTheTest() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay
        let testDay = LocalDay.today.gregorianDay
        let endDay = LocalDay.today.gregorianDay.advanced(by: -1)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: nil),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: nil
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: endDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .updateAndConfirm)
    }

    func testNewConfirmedPositiveResultUpdatedIfExistingPositiveIsNewerThanThePositiveTestDay() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay
        let testDay = LocalDay.today.gregorianDay
        let endDay = LocalDay.today.gregorianDay.advanced(by: -1)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: nil),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: nil
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: endDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .update)
    }

    func testNewConfirmedPositiveResultOverwrittenIfExistingNegativeIsNewerThanThePositiveTestDayAndManualTrigger() {
        let npexDay = LocalDay.today.gregorianDay
        let testDay = LocalDay.today.gregorianDay
        let endDay = LocalDay.today.gregorianDay.advanced(by: -1)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .negative,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: npexDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: endDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwrite)
    }

    func testNewPositiveResultIgnoredIfExistingNegativeIsNewerThanThePositiveTestDay() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay
        let testDay = LocalDay.today.gregorianDay
        let endDay = LocalDay.today.gregorianDay.advanced(by: -1)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: nil),
            testInfo: IndexCaseInfo.TestInfo(
                result: .negative,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: nil
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: endDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .ignore)
    }

    func testNewNegativeResultCompletedIfExistingUnconfirmedPositiveInsideConfirmatoryDayLimit() {
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = LocalDay.today.gregorianDay.advanced(by: -1)
        let newEndDay = LocalDay.today.gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false,
                confirmatoryDayLimit: 1,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .negative,
                testKitType: .labResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .update)
    }

    func testNewNegativeResultCompletedIfExistingUnconfirmedPositiveSameDayConfirmatoryDayLimit() {
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = LocalDay.today.gregorianDay
        let newEndDay = LocalDay.today.gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: true,
                confirmatoryDayLimit: 0,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .negative,
                testKitType: .labResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .update)
    }

    func testNewNegativeResultCompletedIfExistingUnconfirmedPositiveOutsideConfirmatoryDayLimit() {
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let newEndDay = LocalDay.today.gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: true,
                confirmatoryDayLimit: 2,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .negative,
                testKitType: .labResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .complete)
    }

    func testSymptomsAfterPositiveNewNegativeResultCompletedAndDeleteSymptomsIfExistingUnconfirmedPositiveOutsideConfirmatoryDayLimit() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay.advanced(by: -2)
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let newEndDay = LocalDay.today.gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: true,
                confirmatoryDayLimit: 2,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .negative,
                testKitType: .labResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .completeAndDeleteSymptoms)
    }

    func testSymptomsAfterPositiveNewNegativeResultCompletedIfExistingUnconfirmedPositiveOutsideConfirmatoryDayLimit() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay.advanced(by: -2)
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let newEndDay = LocalDay.today.gregorianDay.advanced(by: -3)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: true,
                confirmatoryDayLimit: 0,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .negative,
                testKitType: .labResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .complete)
    }

    func testSymptomsAfterPositiveNewNegativeResultNothingIfExistingUnconfirmedPositiveEndDateIsNewer() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay.advanced(by: -2)
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let newEndDay = LocalDay.today.gregorianDay.advanced(by: -5)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: true,
                confirmatoryDayLimit: 2,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .negative,
                testKitType: .labResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .nothing)
    }

    func testSymptomsAfterPositiveNewNegativeResultNothingIfExistingSelfDiagnosisDayIsNewer() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay.advanced(by: -2)
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let newEndDay = LocalDay.today.gregorianDay.advanced(by: -3)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                confirmatoryDayLimit: nil,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .negative,
                testKitType: .labResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .nothing)
    }

    func testSymptomsAfterPositiveNewNegativeResultDeleteSymptomsIfExistingConfirmedPositiveEndDateIsOlder() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay.advanced(by: -2)
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let newEndDay = LocalDay.today.gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                confirmatoryDayLimit: nil,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .negative,
                testKitType: .labResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .deleteSymptoms)
    }

    func testSymptomsAfterPositiveNewPositiveResultUpdateAndConfirmedIfIfExistingConfirmedEndDayIsNewer() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay.advanced(by: -2)
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let newEndDay = LocalDay.today.gregorianDay.advanced(by: -6)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .updateAndConfirm)
    }

    func testSymptomsAfterPositiveNewPositiveResultUpdateIfExistingUnconfirmedEndDayIsNewer() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay.advanced(by: -2)
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let newEndDay = LocalDay.today.gregorianDay.advanced(by: -6)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .update)
    }

    func testSymptomsAfterPositiveNewPositiveResultConfirmedIfExistingUnconfirmedEndDayIsOlderSymptomsNewer() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay.advanced(by: -2)
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let newEndDay = LocalDay.today.gregorianDay.advanced(by: -3)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .confirm)
    }

    func testSymptomsAfterPositiveNewPositiveResultUpdateIfExistingConfirmedEndDayIsOlderSymptomsNewer() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay.advanced(by: -2)
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let newEndDay = LocalDay.today.gregorianDay.advanced(by: -3)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .nothing)
    }

    func testSymptomsAfterPositiveNewPositiveResultNothingIfExistingUnconfirmedEndDayIsOlderSymptomsOlder() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay.advanced(by: -2)
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let newEndDay = LocalDay.today.gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .nothing)
    }

    func testSymptomsAfterPositiveNewPositiveResultUpdateIfExistingConfirmedEndDayIsOlderSymptomsOlder() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay.advanced(by: -2)
        let testDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let testEndDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let newEndDay = LocalDay.today.gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .update)
    }

    func testSymptomsAfterPositiveNewPositiveResultOvewriteIfIndexcaseOutOfIslation() {
        let selfDiagnosisDay = LocalDay.today.gregorianDay.advanced(by: -12)
        let testDay = LocalDay.today.gregorianDay.advanced(by: -14)
        let testEndDay = LocalDay.today.gregorianDay.advanced(by: -14)
        let newEndDay = LocalDay.today.gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .rapidResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: true,
                receivedOnDay: testDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: newEndDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwrite)
    }

    func testNewPositiveUnconfirmedResultIsNewerThenSymptomsAndOlderThenStoredNegativeConfirmedResult() {
        let newPositiveTestResultDay = LocalDay.today.gregorianDay.advanced(by: -2)
        let symptomsDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let storedNegativeResultDay = LocalDay.today.gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: symptomsDay, onsetDay: symptomsDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .negative,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: storedNegativeResultDay,
                testEndDay: storedNegativeResultDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: newPositiveTestResultDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false,
                confirmatoryDayLimit: 1 // don't care
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .ignore)
    }

    func testNewPositiveUnconfirmedResultIsNewerThenSymptomsAndNewerThenStoredNegativeConfirmedResult() {
        let newPositiveTestResultDay = LocalDay.today.gregorianDay
        let symptomsDay = LocalDay.today.gregorianDay.advanced(by: -4)
        let storedNegativeResultDay = LocalDay.today.gregorianDay.advanced(by: -2)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: symptomsDay, onsetDay: symptomsDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .negative,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: storedNegativeResultDay,
                testEndDay: storedNegativeResultDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: newPositiveTestResultDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false,
                confirmatoryDayLimit: 1 // don't care
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwrite)
    }

    func testNewPositiveUnconfirmedResultIsOlderThenSymptomsAndStoredNegativeResultAndIsNotInConfirmatoryDayLimit() {
        let npexDay = LocalDay.today.gregorianDay
        let testDay = LocalDay.today.gregorianDay
        let endDay = LocalDay.today.gregorianDay.advanced(by: -2)
        let symptomsDay = LocalDay.today.gregorianDay.advanced(by: -1)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: symptomsDay, onsetDay: symptomsDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .negative,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: npexDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: endDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false,
                confirmatoryDayLimit: 1
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwriteAndComplete)
    }

    func testNewPositiveUnconfirmedResultIsOlderThenSymptomsAndStoredNegativeResultAndIsInConfirmatoryDayLimit() {
        let npexDay = LocalDay.today.gregorianDay
        let testDay = LocalDay.today.gregorianDay
        let endDay = LocalDay.today.gregorianDay.advanced(by: -2)
        let symptomsDay = LocalDay.today.gregorianDay.advanced(by: -1)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: symptomsDay, onsetDay: symptomsDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .negative,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: npexDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: endDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false,
                confirmatoryDayLimit: 2
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .ignore)
    }

    func testNewPositiveUnconfirmedResultIsOlderThenStoredNegativeResultAndIsNotInConfirmatoryDayLimit() {
        let npexDay = LocalDay.today.gregorianDay
        let testDay = LocalDay.today.gregorianDay
        let endDay = LocalDay.today.gregorianDay.advanced(by: -2)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .negative,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: npexDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: endDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false,
                confirmatoryDayLimit: 1
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwriteAndComplete)
    }

    func testNewPositiveUnconfirmedResultIsOlderThenStoredNegativeResultAndIsInConfirmatoryDayLimit() {
        let npexDay = LocalDay.today.gregorianDay
        let testDay = LocalDay.today.gregorianDay
        let endDay = LocalDay.today.gregorianDay.advanced(by: -1)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .negative,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testDay,
                testEndDay: npexDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        // When
        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: endDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false,
                confirmatoryDayLimit: 1
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .ignore)
    }

    func testRecivedPositiveTestAfterRecentIsolationBecauseOfPosiviveTestAndHavingSymptoms() {

        let selfDiagnosisDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceSelfDiagnosisOnset.days - 1).gregorianDay
        let testEndDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceNPEXDayNoSelfDiagnosis.days - 2).gregorianDay

        let secondRapidTestReceivedDay = LocalDay.today.gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testEndDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .rapidResult,
                endDate: secondRapidTestReceivedDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwrite)
    }

    func testRecivedPositiveTestWithEndDateAfterExpiredIndexIsolationEndDate() {
        let testEndDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceNPEXDayNoSelfDiagnosis.days - 1).gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testEndDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: LocalDay.today.gregorianDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwrite)
    }

    func testRecivedPositiveTestWithEndDateBeforeExpiredConfirmedIndexIsolationEndDate() {
        let testEndDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceNPEXDayNoSelfDiagnosis.days - 1).gregorianDay
        let secondTestEndDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceNPEXDayNoSelfDiagnosis.days)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testEndDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: secondTestEndDay.startOfDay,
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .nothing)
    }

    func testRecivedPositiveTestWithEndDateBeforeExpiredUnconfirmedIndexIsolationEndDate() {
        let testEndDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceNPEXDayNoSelfDiagnosis.days - 1).gregorianDay
        let secondTestEndDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceNPEXDayNoSelfDiagnosis.days)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testEndDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: secondTestEndDay.startOfDay,
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .confirm)
    }

    func testRecivedPositiveTestWithEndDateBeforeExpiredUnconfirmedIndexEndDate() {
        let testEndDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceNPEXDayNoSelfDiagnosis.days - 1).gregorianDay
        let secondTestEndDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceNPEXDayNoSelfDiagnosis.days - 2)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: nil,
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testEndDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: secondTestEndDay.startOfDay,
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .nothing)
    }

    func testReceivedConfirmedPositiveTestWithEndDateOlderThanExpiredSymptomaticIndexIsolationEndDate() {
        let selfDiagnosisDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceSelfDiagnosisOnset.days - 1).gregorianDay
        let testEndDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceSelfDiagnosisOnset.days)

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: nil
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: testEndDay.startOfDay,
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .updateAndConfirm)
    }

    func testRecivedPositiveTestWithEndDateAfterExpiredSymptomaticIndexIsolationEndDate() {
        let selfDiagnosisDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceSelfDiagnosisOnset.days - 1).gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: nil
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: LocalDay.today.gregorianDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwrite)
    }

    func testRecivedPositiveTestWithEndDateAfterExpiredSymptomaticConfirmedIndexIsolationEndDate() {
        let selfDiagnosisDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceSelfDiagnosisOnset.days - 1).gregorianDay
        let testEndDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceNPEXDayNoSelfDiagnosis.days - 1).gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testEndDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: LocalDay.today.advanced(by: -2).gregorianDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .nothing)
    }

    func testRecivedPositiveTestWithEndDateAfterExpiredSymptomaticUnconfirmedIndexIsolationEndDate() {
        let selfDiagnosisDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceSelfDiagnosisOnset.days - 1).gregorianDay
        let testEndDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceNPEXDayNoSelfDiagnosis.days - 1).gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testEndDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: LocalDay.today.advanced(by: -2).gregorianDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .confirm)
    }

    func testSymptomsAfterPositiveTestRecivedPositiveTestWithEndDateAfterExpiredIndexIsolation() {
        let selfDiagnosisDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceSelfDiagnosisOnset.days).gregorianDay
        let testEndDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceNPEXDayNoSelfDiagnosis.days - 1).gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testEndDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: LocalDay.today.gregorianDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwrite)
    }

    func testRecivedPositiveUnconfirmedTestWithEndDateBeforeExpiredIndexIsolationEndDate() {
        let selfDiagnosisDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceNPEXDayNoSelfDiagnosis.days - 1).gregorianDay
        let testEndDay = LocalDay.today.advanced(by: -$instance.isolationConfiguration.indexCaseSinceNPEXDayNoSelfDiagnosis.days).gregorianDay

        let indexCaseInfo = IndexCaseInfo(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: selfDiagnosisDay),
            testInfo: IndexCaseInfo.TestInfo(
                result: .positive,
                testKitType: .labResult,
                requiresConfirmatoryTest: false,
                shouldOfferFollowUpTest: false,
                receivedOnDay: testEndDay,
                testEndDay: testEndDay
            )
        )

        // GIVEN
        $instance.isolationInfo.indexCaseInfo = indexCaseInfo
        let isolationInfo = IsolationInfo(indexCaseInfo: indexCaseInfo)

        let operation = TestResultIsolationOperation(
            currentIsolationState: isolationState,
            storedIsolationInfo: isolationInfo,
            result: VirologyStateTestResult(
                testResult: .positive,
                testKitType: .labResult,
                endDate: LocalDay.today.gregorianDay.startDate(in: .utc),
                diagnosisKeySubmissionToken: nil,
                requiresConfirmatoryTest: true,
                shouldOfferFollowUpTest: false
            ),
            configuration: configuration,
            currentDateProvider: currentDateProvider
        )

        // THEN
        XCTAssertEqual(operation.storeOperation(), .overwrite)
    }
}

private extension IndexCaseInfo {
    init(selfDiagnosisDay: GregorianDay, onsetDay: GregorianDay?, testResult: TestResult?) {
        self.init(
            symptomaticInfo: IndexCaseInfo.SymptomaticInfo(selfDiagnosisDay: selfDiagnosisDay, onsetDay: onsetDay),
            testInfo: testResult.map { TestInfo(result: $0, testKitType: .labResult, requiresConfirmatoryTest: false, shouldOfferFollowUpTest: false, receivedOnDay: .today, testEndDay: nil) }
        )
    }
}
