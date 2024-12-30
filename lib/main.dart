import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:groq/groq.dart';
import 'dart:math';
import 'package:google_cloud_translation/google_cloud_translation.dart';
import 'package:flutter_regex/flutter_regex.dart';

void main() {
  // Initialize Gemini with the API key
  Gemini.init(apiKey: 'AIzaSyCm8KRWGJl7EExDiYlNwUFDNVTd_qdyXCE');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Legal Sphere',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.grey[900],
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  File? _selectedImage;
  late Groq _groq;
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> documents = [];
  List<Map<String, dynamic>> filteredDocuments = [];
  List<List<num>> documentVectors = [];

  final translator = Translation(apiKey: 'AIzaSyDUvtkOPy1QdAJYZzBVjOjBBxnBgRyii10');

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Load JSON file from assets
    final jsonString = await DefaultAssetBundle.of(context).loadString('assets/train.json');
    documents = List<Map<String, dynamic>>.from(json.decode(jsonString));
    filteredDocuments = documents.where((doc) => doc.containsKey('Description') && doc['Description'] != null).toList();
    // print(documents);

    print("Hi");

    // Generate embeddings for each document using Gemini
    documentVectors = await Future.wait(filteredDocuments.map((doc) async {
      // print(doc);
      // print("Description: ${doc['Description']}");
      try {
        final embedding = await _embedTextToVector(doc['Description']);
        print("Processed embedding for: ${doc['Description']}");
        return embedding;
      } catch (e) {
        print("Error processing document: $e");
        return <double>[]; // Handle errors gracefully
      }
    }).toList());

    print("Hello");

    print("documents_list: $documentVectors");

    int emptyVectorsCount = documentVectors.where((vec) => vec.isEmpty).length;
    print("Number of empty vectors: $emptyVectorsCount");

    _groq = Groq(
      apiKey: "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",
      model: "llama3-groq-70b-8192-tool-use-preview",
    );

    _groq.startChat();

    _groq.setCustomInstructionsWith(
        '''
      You are an expert in analyzing and providing actionable insights based on legal contexts. Your task is to identify the relevant laws under the Bharatiya Nyaya Sanhita (BNS) and the Indian Penal Code (IPC), explain them in simple terms, and, if applicable, provide detailed guidance for filing a case.

 Task:
1. Applicable Laws:
   - Identify the relevant sections under BNS and IPC that address the situation.
   - Provide the name and section of the law.(explain the law statement in detailed way to the)
   - Summarize the offense or legal provision in simple terms, ensuring clarity for non-legal audiences.
   - Specify whether the offense is "Cognizable" or "Non-Cognizable."
   - State the punishments clearly, including imprisonment terms, fines, or other penalties.

2. Filing a Complaint (If Applicable):
   - Provide a step-by-step guide for filing a legal complaint.
   - Include necessary details such as where to report, what information/documents to prepare, and whom to contact.
   - Provide specific links and helpline numbers, especially for cases involving women, minors, or heinous crimes.
     - *Example Resources*:
       - National Commission for Women (NCW): Visit [NCW Website](https://ncw.nic.in) or call 1091.
       - Tamil Nadu Helpline: Call 1098 for immediate assistance.
       - State-wise helpline directory: [State Helpline Directory](https://wcd.nic.in/).

3. Actionable Summary:
   - Offer actionable recommendations for safety measures, preserving evidence, and seeking justice.
   - Provide links to legal aid organizations and non-profits for additional support.
   - Ensure that all guidance is specific, concise, and prioritized.

 Important Guidelines:
- Avoid disclaimers or generic explanations about incomplete information.
- Ensure punishments and penalties provided are accurate and up-to-date as per Indian law.
- Format the response clearly, using bullet points or numbered lists for ease of understanding.
- Include helpline details for cases involving women, children, or heinous crimes.
      '''
    );

  }

  Future<String> translateText(String text, String targetLanguage) async {
    try {
      final response = await translator.translate(text: text, to: targetLanguage);
      return response.translatedText ?? text;
    } catch (e) {
      print('Translation error: $e');
      return text;
    }
  }

  Future<String> detectLanguage(String text) async {
    if (text==''){
      return 'en';
    }
    try {
      final response = await translator.detectLang(text: text);
      return response.detectedSourceLanguage ?? 'en';
    } catch (e) {
      print('Language detection error: $e');
      return 'en';
    }
  }

  Future<void> _sendMessage(String prompt) async {

    final sourceLanguage = await detectLanguage(prompt);

    final translatedPrompt = sourceLanguage != 'en'
        ? await translateText(prompt, 'en')
        : prompt;

    print("Translated: $translatedPrompt");

    String extractedText = '';
    if (_selectedImage != null) {
      extractedText = await _sendImageToGemini(_selectedImage!);
    }

    setState(() {
      _messages.add({
        'sender': 'user',
        'text': prompt,
        'image': _selectedImage,
      });
      _selectedImage = null;
    });

    String combinedPrompt = extractedText.isNotEmpty
        ? "$extractedText $prompt"
        : translatedPrompt;

    // Find the best match document using cosine similarity
    final bestMatch = await _getBestMatchingDocument(combinedPrompt);

    print("Best Match: $bestMatch");
    // bestMatch.then((String s){
    //   print("Final Message");
    //   print("$s");
    // });

    // final input_to_groq = '''
    // You are an expert in analyzing and providing actionable insights based on legal contexts. Your task is to identify the relevant laws under the Bharatiya Nyaya Sanhita (BNS) and the Indian Penal Code (IPC), explain them in simple terms, and, if applicable, provide detailed guidance for filing a case.
    //
    // Current Scenario:
    // ${bestMatch}
    //
    // Query:
    // ${combinedPrompt}
    //
    //  Task:
    // 1. Applicable Laws:
    //    - Identify the relevant sections under BNS and IPC that address the situation.
    //    - Provide the name and section of the law.(explain the law statement in detailed way to the)
    //    - Summarize the offense or legal provision in simple terms, ensuring clarity for non-legal audiences.
    //    - Specify whether the offense is "Cognizable" or "Non-Cognizable."
    //    - State the punishments clearly, including imprisonment terms, fines, or other penalties.
    //
    // 2. Filing a Complaint (If Applicable):
    //    - Provide a step-by-step guide for filing a legal complaint.
    //    - Include necessary details such as where to report, what information/documents to prepare, and whom to contact.
    //    - Provide specific links and helpline numbers, especially for cases involving women, minors, or heinous crimes.
    //      - **Example Resources**:
    //        - National Commission for Women (NCW): Visit [NCW Website](https://ncw.nic.in) or call 1091.
    //        - Tamil Nadu Helpline: Call 1098 for immediate assistance.
    //        - State-wise helpline directory: [State Helpline Directory](https://wcd.nic.in/).
    //
    // 3. Actionable Summary:
    //    - Offer actionable recommendations for safety measures, preserving evidence, and seeking justice.
    //    - Provide links to legal aid organizations and non-profits for additional support.
    //    - Ensure that all guidance is specific, concise, and prioritized.
    //
    //  Important Guidelines:
    // - Avoid disclaimers or generic explanations about incomplete information.
    // - Ensure punishments and penalties provided are accurate and up-to-date as per Indian law.
    // - Format the response clearly, using bullet points or numbered lists for ease of understanding.
    // - Include helpline details for cases involving women, children, or heinous crimes.
    // ''';

    final input_to_groq = '''
    Current Scenario:
    ${bestMatch}
    
    Query:
    ${combinedPrompt}
    ''';

    final response = await _sendMessageGroq(input_to_groq);

    print("Groq: $response");

    print("$sourceLanguage");

    final finalResponse = sourceLanguage != 'en'
        ? await translateText(response, sourceLanguage)
        : response;

    final cleanedResponse = finalResponse.replaceAll(RegExp(r'\*'), '');

    setState(() {
      _messages.add({'sender': 'bot', 'text': cleanedResponse});
    });
  }

  Future<String> _sendImageToGemini(File image) async {
    try {
      final result = await Gemini.instance.textAndImage(
        text: '''
        Analyze the given image to determine if it depicts a situation involving harassment, assault, or any scenario that compromises a woman's security or personal safety. Ensure the output is specific and descriptive, suitable for retrieving relevant laws or resources using the RAG model. Follow these steps:

        Detection and Context:
        
        Analyze the image for visual cues indicating harassment, assault, or a violation of personal safety.
        Focus on body language, facial expressions, gestures, and physical dynamics to determine the nature of the situation.
        Output Requirements (if harassment or insecurity is detected):
        
        Category: Classify the scenario into one of the following categories: Assault, Harassment, Sexual Abuse, Eve-Teasing, or Coercion.
        Description: Provide a detailed and concise explanation of the scene, focusing on:
        The emotions and physical state of the woman (e.g., fear, distress, helplessness).
        The nature of the act (e.g., forceful actions, invasion of personal space).
        The dynamics between the individuals involved (e.g., controlling, aggressive, inappropriate).
        Avoid unnecessary or irrelevant details while ensuring clarity about the victim's insecurity.
        General Description (if no harassment/insecurity is detected):
        
        If the image does not depict harassment or insecurity, provide a brief, general description of the image.
        Do not attempt to force a category or include unwarranted inferences.
        Key Guidelines:
        
        Avoid assumptions beyond what is clearly visible in the image.
        Include information about clothing only if it contributes directly to the context of harassment or insecurity.
        The output must prioritize women's security and clearly identify scenarios requiring legal assistance.
        Output Format:
        
        Category: [Choose from Assault, Harassment, Sexual Abuse, Eve-Teasing, Coercion; leave blank for non-harassment images.]
        Description: [Detailed description emphasizing emotions, circumstances, and women's insecurity. For non-harassment images, provide a simple and general description.]

        ''', // Replace with your fixed text prompt
        images: [image.readAsBytesSync()],
      );
      var temp = result?.content?.parts?.last;
      if(temp is TextPart){
        return temp.text;
      }
      else{
        return '';
      }
    } catch (e) {
      print("Error extracting text from image: $e");
      return '';
    }
  }

  Future<List<num>> _embedTextToVector(String text) async {
    int max_tries = 10;
    while(max_tries>0) {
      try {
        final response = await Gemini.instance.embedContent(text);
        return response!;
      }
      catch (error) {
        print(error);
        max_tries=max_tries-1;
      }
    }
    print("Hi");
    return [];
    // print(response);
  }

  Future<void> _selectImage() async {
    try {
      final XFile? pickedImage = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedImage != null) {
        setState(() {
          _selectedImage = File(pickedImage.path);
        });
      }
    } catch (e) {
      print("Error selecting image: $e");
    }
  }

  void _clearSelectedImage() {
    setState(() {
      _selectedImage = null;
    });
  }

  // Cosine similarity function
  double _cosineSimilarity(List<num> vec1, List<num> vec2) {
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < vec1.length; i++) {
      dotProduct += vec1[i] * vec2[i];
      normA += vec1[i] * vec1[i];
      normB += vec2[i] * vec2[i];
    }

    normA = sqrt(normA);
    normB = sqrt(normB);

    if (normA == 0.0 || normB == 0.0) {
      return 0.0;
    }

    return dotProduct / (normA * normB);
  }

  // Find the best match document using cosine similarity
  Future<String> _getBestMatchingDocument(String query) async{
    final queryVector = await _embedTextToVector(query);

    double highestSimilarity = -10000;
    int bestMatchIndex = -1;

    print("length : ${documentVectors.length}");

    for (int i = 1; i < documentVectors.length; i++) {
      if(documentVectors[i].isEmpty){
        continue;
      }
      print(documentVectors[i]);
      double similarity = _cosineSimilarity(queryVector, documentVectors[i]);
      print("$i : $similarity");
      if (similarity > highestSimilarity) {
        highestSimilarity = similarity;
        bestMatchIndex = i;
      }
    }

    // print("Best match $bestMatchIndex");
    print("Best Match: $bestMatchIndex : ${filteredDocuments[bestMatchIndex]}");

    if (bestMatchIndex != -1) {
      print("Returned correctly");
      return filteredDocuments[bestMatchIndex].toString(); // Return the best matching document text
    } else {
      print("Returned wrong 1");
      return "Not found";
    }
  }

  Future<String> _sendMessageGroq(String text) async {
    try {
      GroqResponse response = await _groq.sendMessage(text);
      print(response.choices.last.message.content);
      return response.choices.first.message.content;
    } on GroqException catch (error) {
      print(error);
      return "Groq Error";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/Logo_inv.png', height: 50, width: 50),
            const SizedBox(width: 10,),
            const Text(
              'Legal Sphere',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: Colors.grey[900],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment: message['sender'] == 'user'
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width*0.8,),
                    margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[850],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message['image'] != null)
                          Image.file(
                            message['image'],
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                          ),
                        if (message['text'] != null)
                          Text(
                            message['text'],
                            style: const TextStyle(color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_selectedImage != null)
            Container(
              margin: const EdgeInsets.all(8.0),
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Image.file(
                    _selectedImage!,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Image selected",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    onPressed: _clearSelectedImage,
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Enter your message...',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      filled: true,
                      fillColor: Colors.grey[800],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.image, color: Colors.white),
                  onPressed: _selectImage,
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: () {
                    if (_controller.text.isNotEmpty || _selectedImage != null) {
                      _sendMessage(_controller.text);
                      _controller.clear();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
