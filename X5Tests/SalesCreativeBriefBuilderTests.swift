import XCTest
@testable import X5

final class SalesCreativeBriefBuilderTests: XCTestCase {
    func testCatalogContainsAllClientRequestedAngles() {
        XCTAssertEqual(SalesAngle.all.count, 10)
        XCTAssertEqual(Set(SalesAngle.all.map(\.id)).count, 10)
        XCTAssertEqual(SalesAngle.all.first?.id, "pain")
        XCTAssertEqual(SalesAngle.all.last?.id, "loss_aversion")
    }

    func testPromptExplainsUploadedImageRolesInOrder() {
        let prompt = SalesCreativeBriefBuilder.compose(
            description: "Установка BI-LED линз от 90 000 тенге в Алматы",
            angle: SalesAngle.all[2],
            hasMainPhoto: true,
            hasLogo: true,
            referenceCount: 2
        )

        XCTAssertTrue(prompt.contains("Товар или услуга: Установка BI-LED линз"))
        XCTAssertTrue(prompt.contains("Угол продаж: Через выгоду"))
        XCTAssertTrue(prompt.contains("изображение 1 является основной фотографией"))
        XCTAssertTrue(prompt.contains("изображение 2 является логотипом"))
        XCTAssertTrue(prompt.contains("изображения 3-4 являются референсами стиля"))
        XCTAssertTrue(prompt.contains("Самостоятельно напиши короткий продающий заголовок"))
    }

    func testPromptDoesNotInventImageRolesWhenNothingIsUploaded() {
        let prompt = SalesCreativeBriefBuilder.compose(
            description: "Доставка цветов по Астане",
            angle: SalesAngle.all[0],
            hasMainPhoto: false,
            hasLogo: false,
            referenceCount: 0
        )

        XCTAssertFalse(prompt.contains("Роли загруженных материалов"))
    }
}
