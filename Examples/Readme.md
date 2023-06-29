# Testing

## Resources

### Teacher Web

[Link](https://apple-iap-test.firebaseapp.com/uncategorized/gb-peer-js-teacher.html)

### Student Web

[Link](https://apple-iap-test.firebaseapp.com/uncategorized/gb-peer-js-student.html)

### Teacher iOS

ViewControllerCallAsTeacher.swift

### Student iOS

ViewControllerCallAsStudent.swift

## Scenarios

### Teacher Web vc Student iOS

| Teacher Web                  | Student iOS                         |
|------------------------------|-------------------------------------|
| Open Web Page                |                                     |
| Setup <selected turn server> |                                     |
|                              | Change turn server in viewDidAppear |
|                              | Open App                            |

### Teacher iOS vc Student Web

| Teacher iOS                         | Student Web                  |
|-------------------------------------|------------------------------|
| Change turn server in viewDidAppear |                              |
| Open App                            |                              |
|                                     | Open Web Page                |
|                                     | Setup <selected turn server> |
|                                     | Start Call                   |
