// ignore_for_file: public_member_api_docs, sort_constructors_first
class Book {
  final String name;
  final int pages;
  final String? imageUrl;

  Book({
    required this.name,
    required this.pages,
    required this.imageUrl,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'pages': pages,
      'imageUrl': imageUrl,
    };
  }

  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      name: map['name'] as String,
      pages: map['pages'] as int,
      imageUrl: map['imageUrl'] as String?,
    );
  }
}
