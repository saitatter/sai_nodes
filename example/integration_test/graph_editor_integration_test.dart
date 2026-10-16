import 'package:integration_test/integration_test.dart';
import '../../packages/sai_nodes/test/graph_editor_test.dart' as editor;
import '../../packages/sai_nodes/test/graph_scene_test.dart' as scene;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  editor.main();
  scene.main();
}
