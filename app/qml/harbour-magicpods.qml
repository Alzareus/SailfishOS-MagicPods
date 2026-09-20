import QtQuick 2.6
import Sailfish.Silica 1.0
import "pages"
import "cover"

ApplicationWindow {
    id: app

    Backend {
        id: backendItem
    }

    initialPage: Component {
        MainPage {
            backend: backendItem
        }
    }

    cover: Component {
        CoverPage {
            backend: backendItem
        }
    }

    allowedOrientations: Orientation.All
}
